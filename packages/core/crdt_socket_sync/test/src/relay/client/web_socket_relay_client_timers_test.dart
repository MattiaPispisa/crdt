import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:test/test.dart';

/// A minimal relay transport for liveness tests: always answers the hello
/// with a welcome; whether it answers pings with pongs is toggled by
/// [respondToPings] to simulate a healthy or half-open connection.
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
    fromJson: (json) => RelayMessage.fromJson(json) ?? Message.fromJson(json),
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

    if (message is RelayHelloMessage) {
      _push(
        RelayWelcomeMessage(
          documentId: documentId,
          sessionId: 'session-1',
          changes: const [],
          seq: 0,
          logLength: 0,
          compact: false,
        ),
      );
    } else if (message is PingMessage && respondToPings) {
      _push(
        PongMessage(
          documentId: documentId,
          originalTimestamp: message.timestamp,
          responseTimestamp: message.timestamp,
        ),
      );
    }
  }

  void _push(Message message) {
    if (_closed || _incoming.isClosed) return;
    final data = _codec.encode(message);
    if (data != null) _incoming.add(data);
  }

  /// Simulate a transport failure.
  void fail() {
    if (!_incoming.isClosed) {
      _incoming.addError(Exception('connection lost'));
    }
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
  group('RelayProtocol.reconnectDelay', () {
    test('doubles per attempt up to the cap', () {
      const base = Duration(milliseconds: 100);
      const max = Duration(milliseconds: 800);

      Duration delay(int attempts) => RelayProtocol.reconnectDelay(
            attempts,
            baseDelay: base,
            maxDelay: max,
            jitter: Duration.zero,
          );

      expect(delay(0), const Duration(milliseconds: 100));
      expect(delay(1), const Duration(milliseconds: 200));
      expect(delay(2), const Duration(milliseconds: 400));
      expect(delay(3), max);
      expect(delay(50), max, reason: 'huge attempt counts must not overflow');
    });

    test('adds bounded jitter', () {
      const jitter = Duration(milliseconds: 100);
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final delay = RelayProtocol.reconnectDelay(
          0,
          jitter: jitter,
          random: random,
        );
        final extra = delay - RelayProtocol.reconnectBaseDelay;
        expect(extra, greaterThanOrEqualTo(Duration.zero));
        expect(extra, lessThanOrEqualTo(jitter));
      }
    });
  });

  group('WebSocketRelayClient liveness and reconnect', () {
    const documentId = 'room-1';
    // Short, injected durations keep the test fast and deterministic.
    // pingTimeout is deliberately wide relative to pingInterval (see the
    // CRDT client timers test for the rationale).
    const pingInterval = Duration(milliseconds: 50);
    const pingTimeout = Duration(milliseconds: 500);

    WebSocketRelayClient buildClient({
      required Transport Function() transportFactory,
      int? maxReconnectAttempts,
    }) {
      final doc = CRDTDocument(
        peerId: PeerId.generate(),
        documentId: documentId,
      );
      final client = WebSocketRelayClient.test(
        url: 'ws://localhost:0',
        document: doc,
        author: doc.peerId,
        pingInterval: pingInterval,
        pingTimeout: pingTimeout,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectBaseDelay: const Duration(milliseconds: 10),
        reconnectMaxDelay: const Duration(milliseconds: 40),
        reconnectJitter: Duration.zero,
        transportFactory: transportFactory,
      );
      addTearDown(client.dispose);
      return client;
    }

    test('stays connected while the relay answers pings with pongs', () async {
      final client = buildClient(
        transportFactory: () =>
            _FakeTransport(documentId: documentId, respondToPings: true),
      );

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      expect(await client.connect(), isTrue);

      await Future<void>.delayed(pingTimeout * 2);

      expect(client.connectionStatusValue, ConnectionStatus.connected);
      expect(
        statuses,
        isNot(contains(ConnectionStatus.reconnecting)),
        reason: 'a healthy connection must never trigger a reconnect',
      );

      await sub.cancel();
    });

    test('detects a half-open connection and reconnects when pongs stop',
        () async {
      final client = buildClient(
        transportFactory: () =>
            _FakeTransport(documentId: documentId, respondToPings: false),
      );

      expect(await client.connect(), isTrue);

      await client.connectionStatus
          .firstWhere((s) => s == ConnectionStatus.reconnecting)
          .timeout(const Duration(seconds: 2));
    });

    test('reconnects with backoff until the transport recovers', () async {
      var attempts = 0;
      late _FakeTransport first;
      final client = buildClient(
        transportFactory: () {
          attempts++;
          // The connection works, drops, and the first reconnect attempts
          // hit a dead transport before it comes back.
          if (attempts == 1) {
            return first = _FakeTransport(
              documentId: documentId,
              respondToPings: true,
            );
          }
          if (attempts < 4) {
            throw Exception('connection refused');
          }
          return _FakeTransport(
            documentId: documentId,
            respondToPings: true,
          );
        },
      );

      expect(await client.connect(), isTrue);

      // A transport error triggers the reconnect loop, which by default
      // retries forever until it succeeds.
      first.fail();
      await client.connectionStatus
          .firstWhere((s) => s == ConnectionStatus.reconnecting)
          .timeout(const Duration(seconds: 2));
      await client.connectionStatus
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 2));

      expect(attempts, greaterThanOrEqualTo(4));
    });

    test('stops after maxReconnectAttempts and reports the error', () async {
      var attempts = 0;
      late _FakeTransport first;
      final client = buildClient(
        maxReconnectAttempts: 2,
        transportFactory: () {
          attempts++;
          if (attempts == 1) {
            return first = _FakeTransport(
              documentId: documentId,
              respondToPings: true,
            );
          }
          throw Exception('connection refused');
        },
      );

      expect(await client.connect(), isTrue);
      first.fail();

      // Give the bounded reconnect loop time to exhaust its attempts.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(client.connectionStatusValue, ConnectionStatus.error);
      final attemptsAtStop = attempts;

      // No further attempts once the cap is hit.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(attempts, attemptsAtStop);
    });

    test('disconnect stops the ping timer (no reconnect afterwards)', () async {
      final client = buildClient(
        transportFactory: () =>
            _FakeTransport(documentId: documentId, respondToPings: false),
      );

      await client.connect();
      await client.disconnect();
      expect(client.connectionStatusValue, ConnectionStatus.disconnected);

      final statuses = <ConnectionStatus>[];
      final sub = client.connectionStatus.listen(statuses.add);

      await Future<void>.delayed(pingTimeout);

      expect(client.connectionStatusValue, ConnectionStatus.disconnected);
      expect(statuses, isNot(contains(ConnectionStatus.reconnecting)));

      await sub.cancel();
    });
  });
}
