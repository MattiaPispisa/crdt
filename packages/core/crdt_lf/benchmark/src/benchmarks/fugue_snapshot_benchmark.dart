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

void main() {
  for (final elements in _kElementCounts) {
    for (final tombstones in [false, true]) {
      FugueSnapshotTakeBenchmark(elements: elements, tombstones: tombstones)
          .report();
      FugueSnapshotRestoreBenchmark(
        elements: elements,
        tombstones: tombstones,
      ).report();
    }
  }
}
