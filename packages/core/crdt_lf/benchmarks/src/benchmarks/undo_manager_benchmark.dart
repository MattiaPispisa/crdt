import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

/// What undo costs.
///
/// Three prices, measured apart:
///
/// - **the write path**: every local operation is offered to every
///   [CRDTUndoManager] the document holds, and the one that records the
///   handler builds the inverse right there. A document with no manager must
///   stay exactly what it was before the feature existed;
/// - **the undo itself**: writing the inverses of one step, which is a
///   transaction of ordinary operations;
/// - **the identity chain**: a restored element comes back under a new
///   identity, and every further undo of the same element adds one link to
///   follow. The ping-pong rows are there to show how that grows.

/// A local edit under a document that holds [managers] undo managers.
///
/// The first manager records the handler being typed into; the others record
/// one of their own, which is what a screen with several independent undo
/// scopes looks like. Going from 1 to 5 therefore measures the loop over the
/// list alone — the inverse is built once whatever the count.
class TypingWithManagersBenchmark extends FixedCycleTimedBenchmark {
  /// Creates the benchmark for [keystrokes] characters and [managers]
  /// managers.
  TypingWithManagersBenchmark(this.keystrokes, {required this.managers})
      : super(
          'Fugue text type $keystrokes chars locally '
          '(undo managers: $managers)',
          measuredCycles: 30,
          batches: 3,
        );

  /// How many characters are typed per cycle.
  final int keystrokes;

  /// How many managers the document holds.
  final int managers;

  @override
  void run() {
    final doc = CRDTDocument();
    final text = CRDTFugueTextHandler(doc, 'text');

    if (managers > 0) {
      CRDTUndoManager(doc).track(text);
    }
    for (var i = 1; i < managers; i++) {
      CRDTUndoManager(doc).track(CRDTMapHandler<int>(doc, 'scope$i'));
    }

    for (var i = 0; i < keystrokes; i++) {
      text.insert(i, 'x');
    }
    if (text.length != keystrokes) {
      throw StateError('lost a keystroke');
    }
  }
}

/// One undo followed by one redo, which leaves the value where it started.
///
/// [setup] runs again before each batch, so the identity chain the pairs build
/// up cannot carry over from the warm-up. Inside a batch it still grows by one
/// link per cycle: that is what [UndoRedoPingPongBenchmark] isolates.
abstract class UndoRedoBenchmark extends FixedCycleTimedBenchmark {
  /// Creates the benchmark reported under `name`.
  UndoRedoBenchmark(super.name)
      : super(measuredCycles: 20, batches: 5, settleCycles: 2);

  late CRDTUndoManager _undo;

  /// Builds the document, the handler and the step that will be taken back.
  ///
  /// Returns the manager that recorded that step.
  CRDTUndoManager build();

  @override
  void setup() {
    _undo = build();
    if (!_undo.canUndo) {
      throw StateError('nothing to take back');
    }
  }

  @override
  void run() {
    _undo
      ..undo()
      ..redo();
  }
}

/// Taking back one keystroke, against the size of the document it sits in.
class TextKeystrokeUndoBenchmark extends UndoRedoBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  TextKeystrokeUndoBenchmark(this.size)
      : super('Fugue text undo+redo one keystroke on $size chars');

  /// The number of characters the document holds.
  final int size;

  @override
  CRDTUndoManager build() {
    final doc = CRDTDocument();
    final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a' * size);
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(text);
    text.insert(size ~/ 2, 'x');
    return undo;
  }
}

/// Taking back a delete, against how many elements it took out.
///
/// The inverse of a delete is the expensive one: the handler reads the value
/// of every element the delete names, cuts them into the blocks that go back
/// together, and mints a fresh id for each. A delete of one character and a
/// delete of five hundred are the same single step either way.
class TextDeleteUndoBenchmark extends UndoRedoBenchmark {
  /// Creates the benchmark for a delete of [deleted] characters.
  TextDeleteUndoBenchmark(this.deleted, {required this.size})
      : super('Fugue text undo+redo a $deleted-char delete on $size chars');

  /// How many characters the step takes out.
  final int deleted;

  /// The number of characters the document holds.
  final int size;

  @override
  CRDTUndoManager build() {
    final doc = CRDTDocument();
    final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a' * size);
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(text);
    text.delete(size ~/ 2, deleted);
    return undo;
  }
}

/// Taking back one write on a map: the inverse is one lookup of the key.
class MapUndoBenchmark extends UndoRedoBenchmark {
  /// Creates the benchmark for a map of [size] keys.
  MapUndoBenchmark(this.size) : super('Map undo+redo one set on $size keys');

  /// The number of keys the map holds.
  final int size;

  @override
  CRDTUndoManager build() {
    final doc = CRDTDocument();
    final map = CRDTMapHandler<int>(doc, 'map');
    for (var i = 0; i < size; i++) {
      map.set('k$i', i);
    }
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(map);
    map.set('k0', -1);
    return undo;
  }
}

/// Taking back one add on an OR-Set: the inverse tombstones the tag the add
/// wrote, and that tag is the operation's own stamp.
class ORSetUndoBenchmark extends UndoRedoBenchmark {
  /// Creates the benchmark for a set of [size] values.
  ORSetUndoBenchmark(this.size)
      : super('OR-set undo+redo one add on $size values');

  /// The number of values the set holds.
  final int size;

  @override
  CRDTUndoManager build() {
    final doc = CRDTDocument();
    final set = CRDTORSetHandler<String>(doc, 'set');
    for (var i = 0; i < size; i++) {
      set.add('v$i');
    }
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(set);
    set.add('extra');
    return undo;
  }
}

/// Undo and redo over and over on the same step.
///
/// An element cannot be brought back to life, so every undo restores it under
/// a **new** identity and records that the old one now stands as the new one.
/// A ping-pong leaves one more of those links behind each time round, and the
/// question this asks is whether the walk over them grows with it.
///
/// It does not, and the rows are here to keep it that way. A link is always
/// added at the **end** of a chain, and each undo names the identity the last
/// one gave it, so the walk is one hop however long the ping-pong ran. What
/// grows is the map, not the work — up to
/// [RebuiltIdentities.maxRebuilt], where the oldest link is dropped.
///
/// Read the rows against each other, and read them from x100: the first one
/// still carries the cost of building the document, which the others spread
/// over ten and a hundred times more cycles.
class UndoRedoPingPongBenchmark extends FixedCycleTimedBenchmark {
  /// Creates the benchmark for [cycles] undo/redo pairs.
  UndoRedoPingPongBenchmark(this.cycles, {required this.size})
      : super(
          'Fugue text undo/redo ping-pong x$cycles on $size chars',
          measuredCycles: 3,
          batches: 3,
          settleCycles: 1,
        );

  /// How many undo/redo pairs one cycle runs.
  final int cycles;

  /// The number of characters the document holds.
  final int size;

  @override
  void run() {
    final doc = CRDTDocument();
    final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a' * size);
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(text);
    text.delete(size ~/ 2, 10);

    for (var i = 0; i < cycles; i++) {
      undo
        ..undo()
        ..redo();
    }
    if (text.length != size - 10) {
      throw StateError('the ping-pong did not come back');
    }
  }
}

void main() {
  for (final managers in [0, 1, 2, 3, 5]) {
    TypingWithManagersBenchmark(300, managers: managers).report();
  }
  for (final size in [2000, 10000]) {
    TextKeystrokeUndoBenchmark(size).report();
  }
  for (final deleted in [1, 100, 500]) {
    TextDeleteUndoBenchmark(deleted, size: 5000).report();
  }
  MapUndoBenchmark(5000).report();
  ORSetUndoBenchmark(5000).report();
  for (final cycles in [10, 100, 1000]) {
    UndoRedoPingPongBenchmark(cycles, size: 2000).report();
  }
}
