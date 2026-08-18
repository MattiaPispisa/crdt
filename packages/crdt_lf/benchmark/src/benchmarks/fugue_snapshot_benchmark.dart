import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

const _kElementCounts = [10000, 100000];

/// A document whose Fugue text holds [elements] runes written by one peer.
///
/// With [tombstones] on, every other element is deleted, so the live ids stop
/// being consecutive — the case the snapshot run framing cannot compress.
/// The state is read before returning, so the caller times the snapshot and
/// not the history replay behind it.
CRDTDocument _document({required int elements, required bool tombstones}) {
  final doc = CRDTDocument(peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(doc, 'text');
  doc.runInTransaction(() {
    text.insert(0, 'a' * elements);
  });
  if (tombstones) {
    doc.runInTransaction(() {
      for (var i = 0; i < elements ~/ 2; i += 1) {
        text.delete(i, 1);
      }
    });
  }
  text.value;
  return doc;
}

/// Reads the whole text of a document seeded by [snapshot] alone.
///
/// The handler is created after the import, so the first read is a
/// `computeState()` with nothing but the snapshot seed behind it.
int _restore(Snapshot snapshot) {
  final doc = CRDTDocument(peerId: PeerId.generate())..importSnapshot(snapshot);
  return CRDTFugueTextHandler(doc, 'text').value.length;
}

class FugueSnapshotTakeBenchmark extends BenchmarkBase {
  FugueSnapshotTakeBenchmark({required this.elements, required this.tombstones})
      : super(
          'Fugue text takeSnapshot of $elements elements '
          '(tombstones: $tombstones)',
          emitter: const CustomEmitter(),
        );

  final int elements;
  final bool tombstones;

  late CRDTDocument _doc;

  @override
  void setup() {
    _doc = _document(elements: elements, tombstones: tombstones);
  }

  @override
  void run() {
    _doc.takeSnapshot(pruneHistory: false);
  }
}

class FugueSnapshotRestoreBenchmark extends BenchmarkBase {
  FugueSnapshotRestoreBenchmark({
    required this.elements,
    required this.tombstones,
  }) : super(
          'Fugue text restore of $elements elements from snapshot '
          '(tombstones: $tombstones)',
          emitter: const CustomEmitter(),
        );

  final int elements;
  final bool tombstones;

  late Snapshot _snapshot;

  @override
  void setup() {
    _snapshot =
        _document(elements: elements, tombstones: tombstones).takeSnapshot();
  }

  @override
  void run() {
    _restore(_snapshot);
  }
}

/// Prints the size of the blob the handler writes, and of the whole snapshot.
///
/// A size is not a run time, so it goes out on its own line rather than
/// through the benchmark emitter.
void _reportSize({required int elements, required bool tombstones}) {
  final snapshot =
      _document(elements: elements, tombstones: tombstones).takeSnapshot();
  final handlerBlob = snapshot.data['text']!.length;
  final total = snapshot.toBytes().length;

  // ignore: avoid_print benchmark results
  print(
    'Fugue text snapshot of $elements elements '
    '(tombstones: $tombstones)(Size): '
    '$handlerBlob bytes handler blob | $total bytes total',
  );
}

/// Prints the size of the movable list blob, which is the one 4.0.0 made
/// bigger.
///
/// Its two last-writer-wins clocks went from a bare 8-byte HLC to a 24-byte
/// [OperationId] each, so every element pays 32 bytes more than it did in
/// 3.x. Unlike the Fugue sequence blob there is no run framing to win any of
/// it back: the entries are keyed by identity, one per element.
void _reportMovableListSize(int elements) {
  final doc = CRDTDocument(peerId: PeerId.generate());
  final list = CRDTFugueMovableListHandler<int>(doc, 'movable');
  doc.runInTransaction(() {
    list.insertAll(0, List<int>.generate(elements, (index) => index));
  });
  list.value;

  final snapshot = doc.takeSnapshot();
  final handlerBlob = snapshot.data['movable']!.length;
  final total = snapshot.toBytes().length;

  // ignore: avoid_print benchmark results
  print(
    'Movable list snapshot of $elements elements(Size): '
    '$handlerBlob bytes handler blob | $total bytes total '
    '| ${(handlerBlob / elements).toStringAsFixed(1)} bytes per element',
  );
}

void main() {
  for (final elements in _kElementCounts) {
    for (final tombstones in [false, true]) {
      _reportSize(elements: elements, tombstones: tombstones);
      FugueSnapshotTakeBenchmark(elements: elements, tombstones: tombstones)
          .report();
      FugueSnapshotRestoreBenchmark(
        elements: elements,
        tombstones: tombstones,
      ).report();
    }
  }
  // Only the small size: the blob is linear in the element count, so the
  // bytes-per-element figure is the whole answer, and seeding a 100 000-item
  // movable list costs minutes that every run of this suite would pay.
  _reportMovableListSize(_kElementCounts.first);
}
