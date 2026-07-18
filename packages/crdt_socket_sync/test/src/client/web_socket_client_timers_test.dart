import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:test/test.dart';

/// A fully controllable in-memory [Transport] for exercising the client's
/// ping/pong liveness logic without real sockets or a real server.
///
/// It always answers the handshake so the client can connect. Whether it
/// answers pings with pongs is toggled by [respondToPings], which lets a test
/// simulate a healthy connection or a half-open (silent) one.
class _FakeTransport implements Transport {
  _FakeTransport({
    required this.documentId,
    required this.respondToPings,
  });

  final String documentId;
  final bool respondToPings;

  final _incoming = StreamController<List<int>>.broadcast();
  final _codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: Message.fromJson,
  );

  bool _closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isConnected => !_closed;

  @override
  Future<void> send(List<int> data) async {
    final message = _codec.decode(data);
    if (message == null) return;

    if (message.type == MessageType.handshakeRequest) {
      _push(
        HandshakeResponseMessage(
          documentId: documentId,
          sessionId: 'session-1',
          versionVector: VersionVector({}),
          changes: const [],
        ),
      );
    } else if (message.type == MessageType.ping && respondToPings) {
      final ping = message as PingMessage;
      _push(
        PongMessage(
          documentId: documentId,
          originalTimestamp: ping.timestamp,
          responseTimestamp: ping.timestamp,
        ),
      );
    }
  }

  void _push(Message message) {
    if (_closed || _incoming.isClosed) return;
    final data = _codec.encode(message);
    if (data != null) _incoming.add(data);
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }
}

void main() {
  group('WebSocketClient ping/pong liveness', () {
    const documentId = 'doc';
    // Short, injected durations keep the test fast and deterministic.
    //
    // pingTimeout is deliberately wide relative to pingInterval: the liveness
    // check trips only when the gap between two processed pongs exceeds it.
    // Under dart2js in a headless browser the event loop is coarse and bursty,
    // so a tight timeout produced intermittent false reconnects. The margin
    // keeps the healthy test robust while staying fast.
    const pingInterval = Duration(milliseconds: 50);
    const pingTimeout = Duration(milliseconds: 500);

    WebSocketClient buildClient({required bool respondToPings}) {
      final doc = CRDTDocument(
        peerId: PeerId.generate(),
        documentId: documentId,
      );
      return WebSocketClient.test(
        url: 'ws://localhost:0',
        document: doc,
        author: doc.peerId,
        pingInterval: pingInterval,
        pingTimeout: pingTimeout,
        transportFactory: () => _FakeTransport(
          documentId: documentId,
          respondToPings: respondToPings,
        ),
      );
    }

    test('stays connected while the server answers pings with pongs', () async {
      final client = buildClient(respondToPings: true);
      addTearDown(client.dispose);

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      final connected = await client.connect();
      expect(connected, isTrue);

      // Beyond pingTimeout: several ping/pong round-trips happen, so staying
      // connected proves fresh pongs sustain it (not just the seeded stamp).
      await Future<void>.delayed(pingTimeout * 2);

      expect(client.connectionStatusValue, ConnectionStatus.connected);
      expect(
        statuses,
        isNot(contains(ConnectionStatus.reconnecting)),
        reason: 'a healthy connection must never trigger a reconnect',
      );
      expect(statuses, isNot(contains(ConnectionStatus.error)));

      await sub.cancel();
    });

    test('detects a half-open connection and reconnects when pongs stop',
        () async {
      final client = buildClient(respondToPings: false);
      addTearDown(client.dispose);

      final connected = await client.connect();
      expect(connected, isTrue);
      expect(client.connectionStatusValue, ConnectionStatus.connected);

      // Regression: with no pong tracking the client stayed "connected"
      // forever on a dead link. It must now detect the timeout and reconnect.
      await client.connectionStatus
          .firstWhere((s) => s == ConnectionStatus.reconnecting)
          .timeout(const Duration(seconds: 2));
    });

    test('disconnect stops the ping timer (no reconnect afterwards)', () async {
      final client = buildClient(respondToPings: false);
      addTearDown(client.dispose);

      await client.connect();
      await client.disconnect();
      expect(client.connectionStatusValue, ConnectionStatus.disconnected);

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      // Past a full ping-timeout window: a cancelled timer must not fire
      // liveness checks or flip the client into reconnecting.
      await Future<void>.delayed(pingTimeout);

      expect(client.connectionStatusValue, ConnectionStatus.disconnected);
      expect(statuses, isNot(contains(ConnectionStatus.reconnecting)));

      await sub.cancel();
    });
  });
}
