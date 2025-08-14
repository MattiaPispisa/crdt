import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';

const _documentId = '30669830-9256-4320-9ed5-f1860cd47d9f';
final _author = PeerId.parse('97a6b8b3-fffc-4ebe-8dd4-f94e6a01c52f');

final serverRegistry = InMemoryCRDTServerRegistry(
  documents: {
    _documentId: CRDTDocument(documentId: _documentId, peerId: _author),
  },
);

// simulate a client request to the server
CRDTDocument getServerRegistryDocument() {
  return CRDTDocument(documentId: _documentId, peerId: _author);
}
