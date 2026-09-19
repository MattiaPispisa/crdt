import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:test/test.dart';

/// A transport that answers the handshake, captures decoded outgoing messages
/// in [sent], and lets a test push arbitrary inbound messages via [push].
class _DriverTransport implements Transport {
  _DriverTransport(this.documentId);

  final String documentId;
  final _incoming = StreamController<List<int>>.broadcast();
  final _codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: (json) => SyncMessage.fromJson(json) ?? Message.fromJson(json),
  );
  final List<Message> sent = [];
  bool _closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isConnected => !_closed;

  @override
  Future<void> send(List<int> data) async {
    final message = _codec.decode(data);
    if (message == null) return;
    sent.add(message);
    if (message.type == MessageType.handshakeRequest) {
      push(
        HandshakeResponseMessage(
          documentId: documentId,
          sessionId: 'session-1',
          versionVector: VersionVector({}),
          changes: const [],
        ),
      );
    }
  }

  void push(Message message) {
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

/// Bundles a client with the transport driving it.
class _Setup {
  _Setup(this.client, this.transport);
  final WebSocketClient client;
  final _DriverTransport transport;
}

void main() {
  group('WebSocketClient behavior', () {
    const documentId = 'doc';

    _Setup build() {
      final transport = _DriverTransport(documentId);
      final doc = CRDTDocument(
        peerId: PeerId.generate(),
        documentId: documentId,
      );
      final client = WebSocketClient.test(
        url: 'ws://localhost:0',
        document: doc,
        author: doc.peerId,
        // Keep the ping timer out of the way of these message-level assertions.
        pingInterval: const Duration(hours: 1),
        transportFactory: () => transport,
      );
      return _Setup(client, transport);
    }

    test('sendMessage before connect throws StateError', () async {
      final setup = build();
      addTearDown(setup.client.dispose);

      await expectLater(
        setup.client.sendMessage(
          Message.ping(documentId: documentId, timestamp: 0),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an out-of-sync error triggers a document status request', () async {
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      setup.transport.sent.clear();

      setup.transport.push(
        Message.error(
          documentId: documentId,
          code: Protocol.errorOutOfSync,
          message: 'out of sync',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        setup.transport.sent.whereType<DocumentStatusRequestMessage>(),
        hasLength(1),
      );
    });

    test('a generic error puts the client in the error state', () async {
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      expect(setup.client.connectionStatusValue, ConnectionStatus.connected);

      setup.transport.push(
        Message.error(
          documentId: documentId,
          code: Protocol.errorInternalError,
          message: 'boom',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(setup.client.connectionStatusValue, ConnectionStatus.error);
    });

    test('an error that names no document still reaches the client', () async {
      // The server answers a frame it could not read, so it cannot say which
      // document the answer is about. Dropping it would leave the client
      // waiting for the reply that error is.
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      expect(setup.client.connectionStatusValue, ConnectionStatus.connected);

      setup.transport.push(
        Message.error(
          documentId: '',
          code: Protocol.errorInvalidMessage,
          message: 'This frame could not be read.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(setup.client.connectionStatusValue, ConnectionStatus.error);
    });

    test('another message that names no document is dropped', () async {
      // Only an error is exempt from the address check: anything else with an
      // empty document id is a frame this client has no reason to act on.
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      setup.transport.sent.clear();

      // A ping is the one frame with a visible answer: a pong goes back.
      setup.transport.push(
        Message.ping(documentId: '', timestamp: 0),
      );
      await Future<void>.delayed(Duration.zero);

      expect(setup.transport.sent.whereType<PongMessage>(), isEmpty);
    });

    test('sendChange sends a change message to the server', () async {
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      setup.transport.sent.clear();

      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        authorDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'x');
      final change = authorDoc.exportChanges().first;

      await setup.client.sendChange(change);

      expect(setup.transport.sent.whereType<ChangeMessage>(), hasLength(1));
    });

    test('local document changes are forwarded to the server', () async {
      final setup = build();
      addTearDown(setup.client.dispose);

      await setup.client.connect();
      setup.transport.sent.clear();

      // Mutating the local document emits a local change that the sync manager
      // forwards to the server.
      CRDTListHandler<String>(
        setup.client.document,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'y');
      await Future<void>.delayed(Duration.zero);

      expect(setup.transport.sent.whereType<ChangeMessage>(), hasLength(1));
    });
  });
}
