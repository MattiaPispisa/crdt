import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

class ConcurrentChangesBenchmark extends BenchmarkBase {
  ConcurrentChangesBenchmark()
      : super(
          'Import 1000 concurrent changes',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc1;
  late final CRDTDocument doc2;
  late final List<Change> changes1;
  late final List<Change> changes2;

  @override
  void setup() {
    doc1 = CRDTDocument(peerId: PeerId.generate());
    doc2 = CRDTDocument(peerId: PeerId.generate());

    final list1 = CRDTListHandler<String>(doc1, 'list');
    final list2 = CRDTListHandler<String>(doc2, 'list');

    // Create 1000 interleaved changes from two documents
    final random = Random();
    for (var i = 0; i < 500; i++) {
      list1.insert(random.nextInt(list1.length + 1), 'item $i');
      list2.insert(random.nextInt(list2.length + 1), 'item $i');
    }

    changes1 = doc1.exportChanges();
    changes2 = doc2.exportChanges();
  }

  @override
  void run() {
    CRDTDocument(peerId: PeerId.generate())
      ..importChanges(changes1)
      ..importChanges(changes2);
  }
}

void main() {
  ConcurrentChangesBenchmark().report();
}
