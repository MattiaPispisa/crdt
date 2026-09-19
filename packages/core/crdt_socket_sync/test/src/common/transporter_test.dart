import 'dart:async';

import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:test/test.dart';

/// A connection whose incoming stream the test drives.
class _FakeConnection implements TransportConnection {
  final _incoming = StreamController<List<int>>();
  final List<List<int>> sent = [];
  bool _connected = true;

  /// Ends the incoming stream, the way a peer closing the socket does.
  Future<void> peerCloses() async {
    _connected = false;
    await _incoming.close();
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> send(List<int> data) async => sent.add(data);

  @override
  Future<void> close() async {
    _connected = false;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  bool get isConnected => _connected;
}

class _FakeConnector implements TransportConnector {
  final List<_FakeConnection> opened = [];

  @override
  Future<TransportConnection> connect() async {
    final connection = _FakeConnection();
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
