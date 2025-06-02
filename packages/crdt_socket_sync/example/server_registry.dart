import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';

final _author = PeerId.parse('30669830-9256-4320-9ed5-f1860cd47d9f');

final serverRegistry = InMemoryCRDTServerRegistry(
  documents: {
    _author.toString(): CRDTDocument(peerId: _author),
  },
);

// simulate a client request to the server
CRDTDocument getServerRegistryDocument() {
  return CRDTDocument(peerId: _author);
}
