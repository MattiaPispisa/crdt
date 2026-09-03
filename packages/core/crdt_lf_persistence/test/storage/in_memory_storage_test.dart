import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';

void main() {
  runDocumentStorageConformanceTests(
    name: 'InMemoryDocumentStorage',
    open: (documentId) async => InMemoryDocumentStorage(documentId),
    // Nothing survives the process, so there is nothing to reopen.
    durable: false,
  );
}
