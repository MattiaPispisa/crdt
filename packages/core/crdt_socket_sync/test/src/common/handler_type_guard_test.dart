import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:test/test.dart';

WebSocketClient _client(CRDTDocument document) => WebSocketClient(
      url: 'ws://127.0.0.1:1',
      document: document,
      author: document.peerId,
    );

void main() {
  group('connect() refuses a minification-unstable type tag', () {
    test('a generic handler without an explicit tag is caught', () async {
      // Its tag would be `CRDTListHandler<String>` on the VM and a minified
      // name in a Flutter web release, so the same build routes changes in
      // debug and silently stops in production.
      final document = CRDTDocument();
      CRDTListHandler<String>(document, 'todos');

      await expectLater(
        _client(document).connect(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('CRDTListHandler<String>'),
              contains('todos'),
              contains('handlerType'),
            ),
          ),
        ),
      );
    });

    test('the same handler passes once it carries a spec', () async {
      final document = CRDTDocument();
      CRDTListHandler<String>(document, 'todos', handlerType: 'todos');

      // No server on that port, so the connection fails — the point is that
      // it fails as a connection, not as a refused tag.
      await expectLater(_client(document).connect(), completion(isFalse));
    });

    test('a built-in handler carries its own constant', () async {
      final document = CRDTDocument();
      CRDTFugueTextHandler(document, 'text');

      await expectLater(_client(document).connect(), completion(isFalse));
    });
  });
}
