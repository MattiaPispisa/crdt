import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

class SnapshotBenchmark extends BenchmarkBase {
  SnapshotBenchmark()
      : super(
          'Take snapshot with 1000 changes',
          emitter: const CustomEmitter(),
        );

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
