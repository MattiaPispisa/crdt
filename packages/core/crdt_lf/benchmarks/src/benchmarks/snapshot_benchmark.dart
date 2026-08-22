import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

class SnapshotBenchmark extends TimedBenchmarkBase {
  SnapshotBenchmark() : super('Take snapshot with 1000 changes');

  late final CRDTDocument doc;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
  }

  @override
  void run() {
    doc.takeSnapshot();
  }
}

void main() {
  SnapshotBenchmark().report();
}
