import 'dart:async';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

/// What watching a handler's deltas costs.
///
/// Every row runs twice: once with nobody watching, which must stay exactly
/// what the handler cost before this feature existed, and once with one
/// subscriber, which is where the work moves.
///
/// A watched handler pays two things a plain one does not:
/// - the decode and the apply of a remote change happen when it **arrives**
///   instead of at the next read (the queue cannot wait for a read that may
///   never come);
/// - the operation reports what it did, which for the Fugue handlers is one
///   `O(√n)` query per operation.
abstract class DeltaEmissionBenchmark<H extends Handler<dynamic>>
    extends TimedBenchmarkBase {
  /// Creates the benchmark reported under `name`.
  DeltaEmissionBenchmark(super.name, {required this.watched})
      : super(runsPerMeasure: 1);

  static const _warmupCycles = 20;
  static const _measuredCycles = 200;

  /// Whether a subscriber is attached to the receiving handler.
  final bool watched;

  /// Creates the handler under test. Both peers use the same id.
  H createHandler(CRDTDocument doc);

  /// Fills the source handler with the starting content.
  void seed(H handler);

  /// Applies the [round]-th edit to the source handler.
  void edit(H handler, int round);

  /// Reads the public value of the handler.
  void read(H handler);

  /// Subscribes to the handler's deltas.
  StreamSubscription<Object?> subscribe(H handler);

  late final CRDTDocument _source;
  late final H _sourceHandler;
  late final CRDTDocument _target;
  late final H _targetHandler;
  StreamSubscription<Object?>? _subscription;
  late List<Change> _pending;

  @override
  void setup() {
    _source = CRDTDocument();
    _sourceHandler = createHandler(_source);
    seed(_sourceHandler);

    _target = CRDTDocument();
    _targetHandler = createHandler(_target);
    _target.importChanges(_source.exportChanges());

    // Warm the cache: a handler with nothing cached has nothing to advance.
    read(_targetHandler);

    if (watched) {
      _subscription = subscribe(_targetHandler);
    }
  }

  @override
  void teardown() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _prepare(int round) {
    edit(_sourceHandler, round);
    _pending = _source.exportChanges(
      fromVersionVector: _target.getVersionVector(),
    );
  }

  @override
  void run() {
    _target.importChanges(_pending);
    read(_targetHandler);
  }

  /// Runs a fixed number of cycles instead of "as many as fit in two seconds".
  ///
  /// Every cycle grows the document, so the default loop would end up
  /// measuring something much larger than what [setup] built.
  @override
  double measure() {
    setup();

    for (var round = 0; round < _warmupCycles; round++) {
      _prepare(round);
      run();
    }

    final stopwatch = Stopwatch();
    for (var round = 0; round < _measuredCycles; round++) {
      _prepare(_warmupCycles + round);
      stopwatch.start();
      run();
      stopwatch.stop();
    }

    teardown();
    return stopwatch.elapsedMicroseconds / _measuredCycles;
  }
}

/// The Fugue text handler, whose delta costs one positional query.
class FugueTextDeltaBenchmark
    extends DeltaEmissionBenchmark<CRDTFugueTextHandler> {
  /// Creates the benchmark for a document of [size] characters.
  FugueTextDeltaBenchmark(this.size, {required super.watched})
      : super(
          'Fugue text remote keystroke + read on $size chars '
          '(watched: $watched)',
        );

  /// The number of characters the document holds.
  final int size;

  @override
  CRDTFugueTextHandler createHandler(CRDTDocument doc) =>
      CRDTFugueTextHandler(doc, 'text');

  @override
  void seed(CRDTFugueTextHandler handler) => handler.insert(0, 'a' * size);

  @override
  void edit(CRDTFugueTextHandler handler, int round) =>
      handler.insert(handler.length, 'x');

  @override
  void read(CRDTFugueTextHandler handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }

  @override
  StreamSubscription<Object?> subscribe(CRDTFugueTextHandler handler) =>
      handler.watch().listen((_) {});
}

/// The index-based text handler, whose delta is a pure function of the
/// operation and the state it lands on.
class TextDeltaBenchmark extends DeltaEmissionBenchmark<CRDTTextHandler> {
  /// Creates the benchmark for a document of [size] characters.
  TextDeltaBenchmark(this.size, {required super.watched})
      : super(
          'Text remote keystroke + read on $size chars (watched: $watched)',
        );

  /// The number of characters the document holds.
  final int size;

  @override
  CRDTTextHandler createHandler(CRDTDocument doc) =>
      CRDTTextHandler(doc, 'text');

  @override
  void seed(CRDTTextHandler handler) => handler.insert(0, 'a' * size);

  @override
  void edit(CRDTTextHandler handler, int round) =>
      handler.insert(handler.length, 'x');

  @override
  void read(CRDTTextHandler handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }

  @override
  StreamSubscription<Object?> subscribe(CRDTTextHandler handler) =>
      handler.watch().listen((_) {});
}

/// The map handler, whose delta is one lookup of the key before the write.
class MapDeltaBenchmark extends DeltaEmissionBenchmark<CRDTMapHandler<int>> {
  /// Creates the benchmark for a map of [size] keys.
  MapDeltaBenchmark(this.size, {required super.watched})
      : super('Map remote write + read on $size keys (watched: $watched)');

  /// The number of keys the map holds.
  final int size;

  @override
  CRDTMapHandler<int> createHandler(CRDTDocument doc) =>
      CRDTMapHandler<int>(doc, 'map');

  @override
  void seed(CRDTMapHandler<int> handler) {
    for (var i = 0; i < size; i++) {
      handler.set('k$i', i);
    }
  }

  @override
  void edit(CRDTMapHandler<int> handler, int round) =>
      handler.set('k${round % size}', round);

  @override
  void read(CRDTMapHandler<int> handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }

  @override
  StreamSubscription<Object?> subscribe(CRDTMapHandler<int> handler) =>
      handler.watch().listen((_) {});
}

/// Local typing: what a watcher adds to the write path.
class LocalTypingDeltaBenchmark extends TimedBenchmarkBase {
  /// Creates the benchmark for [keystrokes] characters.
  LocalTypingDeltaBenchmark(this.keystrokes, {required this.watched})
      : super(
          'Fugue text type $keystrokes chars locally (watched: $watched)',
          runsPerMeasure: 1,
        );

  /// How many characters are typed per measured run.
  final int keystrokes;

  /// Whether a subscriber is attached.
  final bool watched;

  @override
  void run() {
    final doc = CRDTDocument();
    final text = CRDTFugueTextHandler(doc, 'text');
    final subscription = watched ? text.watch().listen((_) {}) : null;

    for (var i = 0; i < keystrokes; i++) {
      text.insert(i, 'x');
    }
    if (text.value.length != keystrokes) {
      throw StateError('lost a keystroke');
    }

    unawaited(subscription?.cancel());
  }
}

void main() {
  for (final size in [2000, 10000]) {
    FugueTextDeltaBenchmark(size, watched: false).report();
    FugueTextDeltaBenchmark(size, watched: true).report();
  }
  for (final size in [2000, 10000]) {
    TextDeltaBenchmark(size, watched: false).report();
    TextDeltaBenchmark(size, watched: true).report();
  }
  for (final size in [1000, 5000]) {
    MapDeltaBenchmark(size, watched: false).report();
    MapDeltaBenchmark(size, watched: true).report();
  }
  for (final keystrokes in [2000]) {
    LocalTypingDeltaBenchmark(keystrokes, watched: false).report();
    LocalTypingDeltaBenchmark(keystrokes, watched: true).report();
  }
}
