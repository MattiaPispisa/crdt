import 'package:persistence_conformance/persistence_conformance.dart';

import 'in_memory_storage.dart';

void main() {
  runDocumentStorageConformanceTests(
    name: 'InMemoryDocumentStorage',
    open: (documentId) async => InMemoryDocumentStorage(documentId),
    // Nothing survives the process, so there is nothing to reopen.
    durable: false,
    synchronous: true,
    openPeerIds: (documentId) async => InMemoryPeerIdStorage(documentId),
  );
}
