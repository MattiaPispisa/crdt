import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server_client/common/common.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_client_session.dart';
import 'package:crdt_socket_sync/src/server_client/server/in_memory_server_registry.dart';
import 'package:test/test.dart';

import '../../utils/fake_connection.dart';

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

/// A compressor that is not the identity, so a frame that went through it is
/// no longer readable as JSON.
///
/// The bug this guards against only shows with one: with [NoCompression] the
/// transport bytes already are the JSON, so every by-hand read of a frame
/// works by accident.
class _Reversing implements Compressor {
  const _Reversing();

  static const int _marker = 0x01;

  @override
  List<int> compress(List<int> data) => [_marker, ...data.reversed];

  @override
  List<int> decompress(List<int> data) {
    if (data.isEmpty || data.first != _marker) {
      throw const FormatException('Not compressed by this compressor');
    }
    return data.skip(1).toList().reversed.toList();
  }
}

void main() {
  // Plain JSON codec matching the session's default wire format, used to
  // encode inbound frames and decode captured outbound frames.
  final codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: (json) => SyncMessage.fromJson(json) ?? Message.fromJson(json),
  );

  group('ClientSession backpressure', () {
    test('closes the session when the outbound buffer overflows', () async {
      final connection = _StallingConnection();
      final session = DocumentClientSession(
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
    late FakeTransportConnection connection;
    late DocumentClientSession session;
    late List<SessionEvent> events;

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
      connection = FakeTransportConnection();
      session = DocumentClientSession(
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

    Future<void> handshake({
      VersionVector? versionVector,
      int protocolVersion = Protocol.protocolVersion,
      SyncCapabilities? capabilities,
    }) async {
      connection.receive(
        codec.encode(
          HandshakeRequestMessage(
            author: PeerId.generate(),
            documentId: documentId,
            versionVector: versionVector ?? VersionVector({}),
            protocolVersion: protocolVersion,
            capabilities: capabilities,
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
        events.where((e) => e.type == SyncSessionEventType.handshakeCompleted),
        hasLength(1),
      );
      expect(session.isSubscribedTo(documentId), isTrue);
    });

    test('refuses a client that speaks another protocol version', () async {
      await registry.addDocument(documentId);
      await handshake(protocolVersion: Protocol.protocolVersion + 1);

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorUnsupportedProtocolVersion);
      // Refused before any state is served.
      expect(decodeSent().whereType<HandshakeResponseMessage>(), isEmpty);
      expect(session.isSubscribedTo(documentId), isFalse);
      expect(connection.isConnected, isFalse);
    });

    test('the version is checked before the document exists', () async {
      // A client on the wrong protocol learns that, not that the document is
      // missing: the version is the more useful answer, and the document
      // lookup can be skipped.
      await handshake(protocolVersion: Protocol.protocolVersion + 1);

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors.single.code, Protocol.errorUnsupportedProtocolVersion);
    });

    /// Fills the server document with real data: a list that was inserted
    /// into and then deleted from, so its changes carry two kinds.
    ///
    /// No handler and no factory is registered on the server document — the
    /// way a server that only stores and forwards holds one.
    Future<String> seedServerDocument() async {
      final author = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(
        author,
        'list',
        handlerType: 'CRDTListHandler<String>',
      )
        ..insert(0, 'x')
        ..delete(0, 1);

      final serverDocument = (await registry.getDocument(documentId))!
        ..importChanges(author.exportChanges());
      expect(serverDocument.registeredHandlers, isEmpty);

      return list.handlerType;
    }

    test('refuses a client missing an operation kind the document holds',
        () async {
      await registry.addDocument(documentId);
      final type = await seedServerDocument();

      await handshake(
        capabilities: SyncCapabilities(
          DocumentCapabilities({
            type: const HandlerFormats(
              operationKinds: {OperationType.kindInsert},
            ),
          }),
        ),
      );

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorUnsupportedClient);
      // The reason names the concrete kind, not just "not supported".
      expect(errors.single.message, contains(type));
      expect(
        errors.single.message,
        contains('kind ${OperationType.kindDelete}'),
      );
      expect(decodeSent().whereType<HandshakeResponseMessage>(), isEmpty);
      expect(connection.isConnected, isFalse);
    });

    test('accepts a client whose capabilities cover the document', () async {
      await registry.addDocument(documentId);
      final type = await seedServerDocument();

      await handshake(
        capabilities: SyncCapabilities(
          DocumentCapabilities({
            type: const HandlerFormats(
              operationKinds: {
                OperationType.kindInsert,
                OperationType.kindDelete,
              },
            ),
          }),
        ),
      );

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
    });

    test('refuses a client whose complete claim leaves out a type in the data',
        () async {
      // "Complete" is the client saying it named every type it can read, so a
      // type it left out really is one it cannot read.
      await registry.addDocument(documentId);
      await seedServerDocument();

      await handshake(
        capabilities: SyncCapabilities(
          DocumentCapabilities({
            'SomeOtherHandler': const HandlerFormats(operationKinds: {0}),
          }),
          complete: true,
        ),
      );

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorUnsupportedClient);
      expect(decodeSent().whereType<HandshakeResponseMessage>(), isEmpty);
    });

    test('accepts the same claim when it does not promise to be complete',
        () async {
      // The ordinary shape of an app: one handler open, connect, open another.
      // A derived claim is partial by construction, so silence about a type
      // cannot be read as "cannot read it" without locking out a good client.
      await registry.addDocument(documentId);
      await seedServerDocument();

      await handshake(
        capabilities: SyncCapabilities(
          DocumentCapabilities({
            'SomeOtherHandler': const HandlerFormats(operationKinds: {0}),
          }),
        ),
      );

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
    });

    test('accepts a client whose description claims nothing', () async {
      // An empty description is not a claim: it means the handlers are not
      // open yet, which is the normal order for an app that connects first.
      // Refusing on it locks a working client out for good, and the latch
      // means it never recovers once the handler does open.
      await registry.addDocument(documentId);
      await seedServerDocument();

      await handshake(capabilities: SyncCapabilities(DocumentCapabilities({})));

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
    });

    test('accepts a client that declares no capabilities at all', () async {
      // Backward compatibility: a 0.8.x client sends no capabilities. With
      // nothing to compare there is nothing to refuse.
      await registry.addDocument(documentId);
      await seedServerDocument();

      await handshake();

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
    });

    test('accepts every client while the document holds no data', () async {
      // Nothing to be unable to read yet, so nothing to refuse.
      await registry.addDocument(documentId);

      await handshake(capabilities: SyncCapabilities(DocumentCapabilities({})));

      expect(decodeSent().whereType<HandshakeResponseMessage>(), hasLength(1));
      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
    });

    test('emits an error for a change to an unsubscribed document', () async {
      await registry.addDocument(documentId);
      // No handshake -> not subscribed.
      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        authorDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'x');
      final change = authorDoc.exportChanges().first;

      connection.receive(
        codec.encode(
          ChangeMessage(change: change, documentId: documentId),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.where((e) => e.type == SessionEventType.error), isNotEmpty);
      expect(
        events.where((e) => e.type == SyncSessionEventType.changeApplied),
        isEmpty,
      );
    });

    test('applies a change from a subscribed client and broadcasts intent',
        () async {
      await registry.addDocument(documentId);
      final serverDoc = (await registry.getDocument(documentId))!;
      CRDTListHandler<String>(
        serverDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      );
      await handshake();

      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        authorDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'x');
      final change = authorDoc.exportChanges().first;

      connection.receive(
        codec.encode(
          ChangeMessage(change: change, documentId: documentId),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        events.where((e) => e.type == SyncSessionEventType.changeApplied),
        hasLength(1),
      );
    });

    test('serves a document status request and subscribes the client',
        () async {
      await registry.addDocument(documentId);

      connection.receive(
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
        events
            .where((e) => e.type == SyncSessionEventType.documentStatusCreated),
        hasLength(1),
      );
    });

    test('errors on a document status request for a missing document',
        () async {
      connection.receive(
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
      CRDTListHandler<String>(
        doc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'x');
      final vv = doc.getVersionVector();

      connection.receive(
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

    test('answers a handshake whose capabilities cannot be read', () async {
      // The whole point of the check is to tell peers apart, so a capability
      // block this build cannot parse deserves an answer. It used to throw
      // inside the codec, be logged, and leave the client waiting on a reply
      // that never came.
      await registry.addDocument(documentId);

      connection.receive(
        utf8.encode(
          jsonEncode({
            'type': MessageType.handshakeRequest.value,
            'documentId': documentId,
            'author': PeerId.generate().toString(),
            'versionVector': base64Encode(VersionVector({}).toBytes()),
            'capabilities': {'MockHandler': 'not an object'},
          }),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final errors = decodeSent().whereType<ErrorMessage>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, Protocol.errorInvalidMessage);
      // The answer names no document: the frame did not decode, so the server
      // does not read one out of it. A client takes an error that names none.
      expect(errors.single.documentId, isEmpty);
      expect(decodeSent().whereType<HandshakeResponseMessage>(), isEmpty);
    });

    test('stays quiet about a frame belonging to a plugin it does not have',
        () async {
      // The peer has a plugin this build does not: a difference in setup, not
      // a fault. Answering would turn every frame of a working connection —
      // one per cursor move, for awareness — into an error the peer displays.
      connection.receive(
        utf8.encode(
          jsonEncode({
            'type': MessageTypeValue.firstPluginValue,
            'documentId': documentId,
          }),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(decodeSent().whereType<ErrorMessage>(), isEmpty);
      // Still reported to whoever runs the server.
      expect(events.where((e) => e.type == SessionEventType.error), isNotEmpty);
    });

    test('names no document in an error about a frame it could not read',
        () async {
      // Not even once the session knows which document it serves: the answer
      // is about a frame, not about a document, and the frame that failed is
      // the one that would have said which.
      await registry.addDocument(documentId);
      await handshake();
      connection.sent.clear();

      connection.receive([0xff, 0xfe, 0x00, 0x01]);
      await Future<void>.delayed(Duration.zero);

      expect(
        decodeSent().whereType<ErrorMessage>().single.documentId,
        isEmpty,
      );
    });

    test('closes the socket when the session dies', () async {
      // Only close() used to close it, so a session that ended any other way
      // left the socket and its subscription alive for the process's life.
      expect(connection.isConnected, isTrue);

      connection.receiveError(StateError('socket broke'));
      await Future<void>.delayed(Duration.zero);

      expect(connection.isConnected, isFalse);
    });

    test('emits an error when an undecodable frame arrives', () async {
      connection.receive([0xff, 0xfe, 0x00, 0x01]);
      await Future<void>.delayed(Duration.zero);

      expect(events.where((e) => e.type == SessionEventType.error), isNotEmpty);
    });

    group('with a compressor that is not the identity', () {
      late FakeTransportConnection compressedConnection;
      late DocumentClientSession compressedSession;
      late CompressedCodec<Message> compressedCodec;

      setUp(() {
        compressedConnection = FakeTransportConnection();
        compressedSession = DocumentClientSession(
          id: 'session-compressed',
          connection: compressedConnection,
          serverRegistry: registry,
          compressor: const _Reversing(),
        );
        compressedCodec =
            CompressedCodec<Message>(codec, compressor: const _Reversing());
      });

      tearDown(() => compressedSession.dispose());

      test('stays quiet about a plugin frame it cannot read', () async {
        // Reading the type out of the raw transport bytes fails here, and the
        // session used to fall through to an error reply — one per frame, on a
        // connection that works.
        compressedConnection.receive(
          compressedCodec.encode(
            Message.ping(documentId: documentId, timestamp: 0),
          )!,
        );
        await Future<void>.delayed(Duration.zero);
        compressedConnection.sent.clear();

        compressedConnection.receive(
          const _Reversing().compress(
            utf8.encode(
              jsonEncode({
                'type': MessageTypeValue.firstPluginValue,
                'documentId': documentId,
              }),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final sent = compressedConnection.sent
            .map(compressedCodec.decode)
            .whereType<Message>();
        expect(sent.whereType<ErrorMessage>(), isEmpty);
      });
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
