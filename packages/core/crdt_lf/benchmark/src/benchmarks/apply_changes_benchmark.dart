import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

class ApplyChangesBenchmark extends BenchmarkBase {
  ApplyChangesBenchmark()
      : super(
          'Apply 1000 changes',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc;
  late final List<Change> changes;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    // Get the changes to be applied during the benchmark
    changes = doc.exportChanges();
  }

  @override
  void run() {
    // Create a new document to apply the changes to
    CRDTDocument(peerId: PeerId.generate()).importChanges(changes);
  }
}

void main() {
  ApplyChangesBenchmark().report();
}
