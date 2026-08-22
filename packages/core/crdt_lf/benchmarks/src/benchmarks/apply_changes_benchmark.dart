import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

class ApplyChangesBenchmark extends TimedBenchmarkBase {
  ApplyChangesBenchmark() : super('Apply 1000 changes');

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
