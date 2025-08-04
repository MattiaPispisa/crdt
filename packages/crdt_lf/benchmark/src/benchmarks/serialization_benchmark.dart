import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

class SerializationBenchmark extends BenchmarkBase {
  late final List<int> binaryChanges;
  late final CRDTDocument doc;

  SerializationBenchmark()
      : super(
          'Binary encode/decode 1000 changes',
          emitter: const CustomEmitter(),
        );

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    binaryChanges = doc.binaryExportChanges();
  }

  @override
  void run() {
    final newDoc = CRDTDocument(peerId: PeerId.generate());
    newDoc.binaryImportChanges(binaryChanges);
  }
}

void main() {
  SerializationBenchmark().report();
}
