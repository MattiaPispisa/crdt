import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/server/client_session.dart';
import 'package:crdt_socket_sync/src/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:test/test.dart';

/// A connection whose sends never complete, so bytes accumulate in the
/// session's outbound queue.
class _StallingConnection implements TransportConnection {
  final _incoming = StreamController<List<int>>();

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> send(List<int> data) => Completer<void>().future;

  @override
  Future<void> close() async {
    await _incoming.close();
  }

  @override
  bool get isConnected => true;
}

/// A controllable bidirectional connection: the test pushes inbound frames on
/// [inbound] and inspects captured outbound frames in [sent].
class _FakeConnection implements TransportConnection {
  final _incoming = StreamController<List<int>>();
  final List<List<int>> sent = [];
  bool _connected = true;

  void inbound(List<int> data) => _incoming.add(data);

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> send(List<int> data) async => sent.add(data);

  @override
  Future<void> close() async {
    _connected = false;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  @override
  bool get isConnected => _connected;
}

void main() {
  // Plain JSON codec matching the session's default wire format, used to
  // encode inbound frames and decode captured outbound frames.
  final codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: Message.fromJson,
  );

  group('ClientSession backpressure', () {
    test('closes the session when the outbound buffer overflows', () async {
      final connection = _StallingConnection();
      final session = ClientSession(
        id: 'session-1',
        connection: connection,
        serverRegistry: InMemoryCRDTServerRegistry(),
        // Any real encoded message exceeds a 1-byte bound.
        maxBufferSize: 1,
      );
      addTearDown(session.dispose);

      final events = <SessionEvent>[];
      session.events.listen(events.add);

      await expectLater(
        session.sendMessage(
          Message.ping(documentId: 'doc', timestamp: 0),
        ),
        throwsA(isA<OutboundBufferOverflow>()),
      );

      await Future<void>.delayed(Duration.zero);

      // The session tears itself down: a client that cannot keep up is dropped
      // and will re-sync from its version vector on the next handshake.
      expect(
        events.where((e) => e.type == SessionEventType.disconnected),
        hasLength(1),
      );
    });
  });

  group('ClientSession message handling', () {
    const documentId = 'doc';
    late InMemoryCRDTServerRegistry registry;
    late _FakeConnection connection;
    late ClientSession session;
    late List<SessionEvent> events;

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
      connection = _FakeConnection();
      session = ClientSession(
        id: 'session-1',
        connection: connection,
        serverRegistry: registry,
      );
      events = [];
      session.events.listen(events.add);
    });

    tearDown(() => session.dispose());

    List<Message> decodeSent() =>
        connection.sent.map(codec.decode).whereType<Message>().toList();

    Future<void> handshake({VersionVector? versionVector}) async {
      connection.inbound(
        codec.encode(
          HandshakeRequestMessage(
            author: PeerId.generate(),
            documentId: documentId,
            versionVector: versionVector ?? VersionVector({}),
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('responds with an error for a handshake on a missing document',
        () async {
      await handshake();

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorDocumentNotFound);
    });

    test('completes the handshake for an existing document', () async {
      await registry.addDocument(documentId);
      await handshake();

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(
        events.where((e) => e.type == SessionEventType.handshakeCompleted),
        hasLength(1),
      );
      expect(session.isSubscribedTo(documentId), isTrue);
    });

    test('emits an error for a change to an unsubscribed document', () async {
      await registry.addDocument(documentId);
      // No handshake -> not subscribed.
      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(authorDoc, 'list').insert(0, 'x');
      final change = authorDoc.exportChanges().first;

      connection.inbound(
        codec.encode(
          ChangeMessage(change: change, documentId: documentId),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.where((e) => e.type == SessionEventType.error), isNotEmpty);
      expect(
        events.where((e) => e.type == SessionEventType.changeApplied),
        isEmpty,
      );
    });

    test('applies a change from a subscribed client and broadcasts intent',
        () async {
      await registry.addDocument(documentId);
      final serverDoc = (await registry.getDocument(documentId))!;
      CRDTListHandler<String>(serverDoc, 'list');
      await handshake();

      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(authorDoc, 'list').insert(0, 'x');
      final change = authorDoc.exportChanges().first;

      connection.inbound(
        codec.encode(
          ChangeMessage(change: change, documentId: documentId),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        events.where((e) => e.type == SessionEventType.changeApplied),
        hasLength(1),
      );
    });

    test('serves a document status request and subscribes the client',
        () async {
      await registry.addDocument(documentId);

      connection.inbound(
        codec.encode(
          DocumentStatusRequestMessage(
            documentId: documentId,
            versionVector: VersionVector({}),
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(decodeSent().whereType<DocumentStatusMessage>(), hasLength(1));
      expect(session.isSubscribedTo(documentId), isTrue);
      expect(
        events.where((e) => e.type == SessionEventType.documentStatusCreated),
        hasLength(1),
      );
    });

    test('errors on a document status request for a missing document',
        () async {
      connection.inbound(
        codec.encode(
          const DocumentStatusRequestMessage(documentId: documentId),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorDocumentNotFound);
    });

    test('replies to a ping with a pong and records the version vector',
        () async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'list').insert(0, 'x');
      final vv = doc.getVersionVector();

      connection.inbound(
        codec.encode(
          PingMessage(documentId: documentId, timestamp: 7, versionVector: vv),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      final pongs = decodeSent().whereType<PongMessage>().toList();
      expect(pongs, hasLength(1));
      expect(pongs.single.originalTimestamp, 7);
      expect(
        events.where((e) => e.type == SessionEventType.pingReceived),
        hasLength(1),
      );
      expect(session.lastKnownVersionVector?.toBytes(), vv.toBytes());
    });

    test('emits an error when an undecodable frame arrives', () async {
      connection.inbound([0xff, 0xfe, 0x00, 0x01]);
      await Future<void>.delayed(Duration.zero);

      expect(events.where((e) => e.type == SessionEventType.error), isNotEmpty);
    });

    test('sending on a closed session emits an error and does not throw',
        () async {
      await session.close();

      await session.sendMessage(
        Message.ping(documentId: documentId, timestamp: 0),
      );

      expect(
        events.where(
          (e) =>
              e is SessionEventGeneric &&
              e.type == SessionEventType.error &&
              e.message.contains('closed'),
        ),
        isNotEmpty,
      );
    });
  });
}
