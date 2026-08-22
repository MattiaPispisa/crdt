import 'dart:typed_data';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

class SerializationBenchmark extends TimedBenchmarkBase {
  SerializationBenchmark() : super('Binary encode/decode 1000 changes');

  late final Uint8List binaryChanges;
  late final CRDTDocument doc;

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
    CRDTDocument(peerId: PeerId.generate()).binaryImportChanges(binaryChanges);
  }
}

void main() {
  SerializationBenchmark().report();
}
