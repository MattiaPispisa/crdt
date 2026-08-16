import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// A peer receives one remote change and the UI reads the new value: the live
/// editing loop, paid once per edit of every other peer.
///
/// The document only advances its cached state when the change extends the
/// replay order (or when the handler's state commutes), so this is also the
/// benchmark that shows the difference against a full history replay.
abstract class RemoteChangeBenchmark<H extends Handler<dynamic>>
    extends BenchmarkBase {
  /// Creates the benchmark reported under `name`.
  RemoteChangeBenchmark(super.name) : super(emitter: const CustomEmitter());

  static const _warmupCycles = 20;
  static const _measuredCycles = 200;

  /// Creates the handler under test. Both peers use the same id.
  H createHandler(CRDTDocument doc);

  /// Fills the source handler with the starting content.
  void seed(H handler);

  /// Applies the [round]-th edit to the source handler.
  void edit(H handler, int round);

  /// Reads the public value of the handler.
  void read(H handler);

  /// Whether the remote change must sort **before** what the target already
  /// folded in.
  ///
  /// The target edits locally first, which moves its clock past the source,
  /// so the change that follows arrives from the past. Only a handler whose
  /// state commutes keeps its cache here; every other one replays its history.
  bool get remoteChangeIsFromThePast => false;

  late final CRDTDocument _source;
  late final H _sourceHandler;
  late final CRDTDocument _target;
  late final H _targetHandler;
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
  }

  /// Produces the next remote change. Kept out of [run] so the score covers
  /// only what the receiving peer does.
  void _prepare(int round) {
    if (remoteChangeIsFromThePast) {
      edit(_targetHandler, round);
      read(_targetHandler);
    }
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
  /// measuring something much larger than what [setup] built — and the size is
  /// exactly what these benchmarks vary.
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

/// The Fugue text handler: its tree commutes, so it always takes the
/// incremental path.
class FugueTextRemoteBenchmark
    extends RemoteChangeBenchmark<CRDTFugueTextHandler> {
  /// Creates the benchmark for a document of [size] characters.
  FugueTextRemoteBenchmark(this.size)
      : super('Fugue text remote keystroke + read on $size chars');

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
}

/// The index-based text handler: it resolves conflicts by replay order, so it
/// takes the incremental path only while the changes arrive in that order.
class TextRemoteBenchmark extends RemoteChangeBenchmark<CRDTTextHandler> {
  /// Creates the benchmark for a document of [size] characters.
  TextRemoteBenchmark(this.size)
      : super('Text remote keystroke + read on $size chars');

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
}

/// The map handler: last-write-wins on the replay order, the case where the
/// order rule is the only thing that makes the incremental path correct.
class MapRemoteBenchmark extends RemoteChangeBenchmark<CRDTMapHandler<int>> {
  /// Creates the benchmark for a map of [size] keys.
  MapRemoteBenchmark(this.size) : super('Map remote set + read on $size keys');

  /// The number of keys the map holds.
  final int size;

  @override
  CRDTMapHandler<int> createHandler(CRDTDocument doc) =>
      CRDTMapHandler<int>(doc, 'map');

  @override
  void seed(CRDTMapHandler<int> handler) {
    for (var i = 0; i < size; i++) {
      handler.set('key$i', i);
    }
  }

  @override
  void edit(CRDTMapHandler<int> handler, int round) =>
      handler.set('key${size + round}', round);

  @override
  void read(CRDTMapHandler<int> handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }
}

/// The OR-set: it picks winners by tag, so it takes the incremental path even
/// for a change that arrives from the past.
class OrSetRemoteBenchmark
    extends RemoteChangeBenchmark<CRDTORSetHandler<int>> {
  /// Creates the benchmark for a set of [size] values.
  OrSetRemoteBenchmark(this.size)
      : super('OR-set remote add from the past + read on $size values');

  /// The number of values the set holds.
  final int size;

  @override
  bool get remoteChangeIsFromThePast => true;

  @override
  CRDTORSetHandler<int> createHandler(CRDTDocument doc) =>
      CRDTORSetHandler<int>(doc, 'set');

  @override
  void seed(CRDTORSetHandler<int> handler) {
    for (var i = 0; i < size; i++) {
      handler.add(i);
    }
  }

  @override
  void edit(CRDTORSetHandler<int> handler, int round) =>
      handler.add(size + round);

  @override
  void read(CRDTORSetHandler<int> handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }
}

/// The OR-map: same as the OR-set, one tag per key-value pair.
class OrMapRemoteBenchmark
    extends RemoteChangeBenchmark<CRDTORMapHandler<String, int>> {
  /// Creates the benchmark for a map of [size] keys.
  OrMapRemoteBenchmark(this.size)
      : super('OR-map remote put from the past + read on $size keys');

  /// The number of keys the map holds.
  final int size;

  @override
  bool get remoteChangeIsFromThePast => true;

  @override
  CRDTORMapHandler<String, int> createHandler(CRDTDocument doc) =>
      CRDTORMapHandler<String, int>(doc, 'or_map');

  @override
  void seed(CRDTORMapHandler<String, int> handler) {
    for (var i = 0; i < size; i++) {
      handler.put('key$i', i);
    }
  }

  @override
  void edit(CRDTORMapHandler<String, int> handler, int round) =>
      handler.put('key${size + round}', round);

  @override
  void read(CRDTORMapHandler<String, int> handler) {
    if (handler.value.isEmpty) {
      throw StateError('empty value');
    }
  }
}

void main() {
  for (final size in [2000, 10000, 30000]) {
    FugueTextRemoteBenchmark(size).report();
  }
  for (final size in [2000, 10000, 30000]) {
    TextRemoteBenchmark(size).report();
  }
  for (final size in [1000, 5000]) {
    MapRemoteBenchmark(size).report();
  }
  for (final size in [1000, 5000]) {
    OrSetRemoteBenchmark(size).report();
  }
  for (final size in [1000, 5000]) {
    OrMapRemoteBenchmark(size).report();
  }
}
