import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

const _kElements = 10000;

/// A document whose Fugue text holds [_kElements] runes written by one peer.
///
/// With [tombstones] on, every other element is deleted, so the live ids stop
/// being consecutive — the case the snapshot run framing cannot compress.
/// The state is read before returning, so the caller times the snapshot and
/// not the history replay behind it.
CRDTDocument _document({required bool tombstones}) {
  final doc = CRDTDocument(peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(doc, 'text');
  doc.runInTransaction(() {
    text.insert(0, 'a' * _kElements);
  });
  if (tombstones) {
    doc.runInTransaction(() {
      for (var i = 0; i < _kElements ~/ 2; i += 1) {
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
  FugueSnapshotTakeBenchmark({required this.tombstones})
      : super(
          'Fugue text takeSnapshot of $_kElements elements '
          '(tombstones: $tombstones)',
          emitter: const CustomEmitter(),
        );

  final bool tombstones;

  late CRDTDocument _doc;

  @override
  void setup() {
    _doc = _document(tombstones: tombstones);
  }

  @override
  void run() {
    _doc.takeSnapshot(pruneHistory: false);
  }
}

class FugueSnapshotRestoreBenchmark extends BenchmarkBase {
  FugueSnapshotRestoreBenchmark({required this.tombstones})
      : super(
          'Fugue text restore of $_kElements elements from snapshot '
          '(tombstones: $tombstones)',
          emitter: const CustomEmitter(),
        );

  final bool tombstones;

  late Snapshot _snapshot;

  @override
  void setup() {
    _snapshot = _document(tombstones: tombstones).takeSnapshot();
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
void _reportSize({required bool tombstones}) {
  final snapshot = _document(tombstones: tombstones).takeSnapshot();
  final handlerBlob = snapshot.data['text']!.length;
  final total = snapshot.toBytes().length;

  // ignore: avoid_print benchmark results
  print(
    'Fugue text snapshot of $_kElements elements '
    '(tombstones: $tombstones)(Size): '
    '$handlerBlob bytes handler blob | $total bytes total',
  );
}

void main() {
  for (final tombstones in [false, true]) {
    _reportSize(tombstones: tombstones);
    FugueSnapshotTakeBenchmark(tombstones: tombstones).report();
    FugueSnapshotRestoreBenchmark(tombstones: tombstones).report();
  }
}
