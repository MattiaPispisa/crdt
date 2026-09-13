import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:test/test.dart';

void main() {
  group('the real WebSocket connector', () {
    test('a connection that cannot be opened fails as a connection', () async {
      // Port 1 has no listener, so this drives the actual
      // `WebSocketChannel.connect` path — every other test swaps in a mock
      // connector and never reaches it. What is pinned here is that a dead
      // endpoint is a failed `connect()`, not a thrown error the caller has to
      // catch.
      final document = CRDTDocument();
      CRDTListHandler<String>(document, 'todos', handlerType: 'todos');

      final client = WebSocketClient(
        url: 'ws://127.0.0.1:1',
        document: document,
        author: document.peerId,
      );

      await expectLater(client.connect(), completion(isFalse));
      expect(
        client.connectionStatusValue,
        isNot(ConnectionStatus.connected),
      );
    });
  });
}
