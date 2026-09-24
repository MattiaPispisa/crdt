import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:test/test.dart';

import '../utils/fake_connection.dart';

class _FakeConnector implements TransportConnector {
  final List<FakeTransportConnection> opened = [];

  @override
  Future<TransportConnection> connect() async {
    final connection = FakeTransportConnection();
    opened.add(connection);
    return connection;
  }
}

void main() {
  group('Transport', () {
    test('reports the peer closing as an error on incoming', () async {
      final connector = _FakeConnector();
      final transport = Transport.create(connector);

      final errors = <Object>[];
      transport.incoming.listen((_) {}, onError: errors.add);

      await transport.send([1]);
      await connector.opened.single.peerCloses();
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
    });

    test('refuses to send once the peer has closed', () async {
      // Without this a send opens a second socket behind the consumer's back:
      // a connection that never handshakes, on a client that looks healthy.
      final connector = _FakeConnector();
      final transport = Transport.create(connector);
      transport.incoming.listen((_) {}, onError: (_) {});

      await transport.send([1]);
      await connector.opened.single.peerCloses();
      await Future<void>.delayed(Duration.zero);

      await expectLater(transport.send([2]), throwsStateError);
      expect(connector.opened, hasLength(1));
    });

    test('opens one socket for a run of sends', () async {
      final connector = _FakeConnector();
      final transport = Transport.create(connector);
      addTearDown(transport.close);

      await transport.send([1]);
      await transport.send([2]);

      expect(connector.opened, hasLength(1));
      expect(connector.opened.single.sent, hasLength(2));
    });
  });
}
