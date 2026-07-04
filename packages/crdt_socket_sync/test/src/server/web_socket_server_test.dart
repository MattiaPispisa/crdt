@TestOn('vm')
library web_socket_server_test;

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../utils/stub.dart';

void main() {
  group('WebSocketServer', () {
    late MockHttpServer mockHttpServer;

    /// http request controller used to simulate incoming http requests
    /// that will be upgraded to websocket
    late StreamController<HttpRequest> httpRequestController;

    /// mock web socket transformer
    late MockWebSocketTransformer mockWebSocketTransformer;

    /// server instance
    late WebSocketServer server;

    /// registry instance
    late InMemoryCRDTServerRegistry registry;
    late List<MockWebSocket> mockWebSockets;

    /// codec instance
    late JsonMessageCodec<Message> codec;

    /// message sent controller used to observe every message
    /// sent from the server to the clients
    late StreamController<List<int>> messagesSent;

    setUp(() {
      messagesSent = StreamController<List<int>>.broadcast();
      mockHttpServer = MockHttpServer();
      httpRequestController = StreamController<HttpRequest>.broadcast();
      registry = InMemoryCRDTServerRegistry();
      mockWebSocketTransformer = MockWebSocketTransformer();
      mockWebSockets = <MockWebSocket>[];
      codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: Message.fromJson,
      );
      server = WebSocketServer.test(
        serverFactory: () async => mockHttpServer,
        serverRegistry: registry,
        serverTransformer: mockWebSocketTransformer,
      );
    });

    tearDown(() {
      server.stop();
      registry.clear();
      httpRequestController.close();
    });

    test('should create a server', () {
      late WebSocketServer server;
      expect(
        () {
          server = WebSocketServer(
            serverFactory: () async => MockHttpServer(),
            serverRegistry: InMemoryCRDTServerRegistry(),
          );
        },
        returnsNormally,
      );

      expect(server.host, '');
      expect(server.port, 0);
      expect(server.serverEvents.isBroadcast, isTrue);
    });

    test('should return false and emit an error when start fails', () async {
      final failingServer = WebSocketServer.test(
        serverFactory: () async => throw Exception('cannot bind'),
        serverRegistry: registry,
        serverTransformer: mockWebSocketTransformer,
      );
      final events = <ServerEvent>[];
      failingServer.serverEvents.listen(events.add);

      final started = await failingServer.start();

      expect(started, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((e) => e.type == ServerEventType.error),
        isNotEmpty,
      );
    });

    test('should start the server', () async {
      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );

      final started = await server.start();
      expect(started, isTrue);

      verify(
        () => mockHttpServer.listen(
          any(),
          onError: any(named: 'onError'),
          cancelOnError: any(named: 'cancelOnError'),
          onDone: any(named: 'onDone'),
        ),
      ).called(1);
    });

    test('should upgrade request to websocket', () async {
      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: mockWebSockets,
        clientSockets: <MockWebSocket>[],
        messagesSent: messagesSent,
      );

      final started = await server.start();
      expect(started, isTrue);

      httpRequestController.add(MockHttpRequest());

      await Future<void>.delayed(Duration.zero);

      verify(() => mockWebSocketTransformer.upgrade(any())).called(1);
    });

    test('should create a session', () async {
      final completer = Completer<ServerEvent>();

      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: mockWebSockets,
        clientSockets: <MockWebSocket>[],
        messagesSent: messagesSent,
      );

      server.serverEvents.listen((data) {
        if (data.type == ServerEventType.clientConnected) {
          completer.complete(data);
        }
      });
      await server.start();

      httpRequestController.add(MockHttpRequest());

      final event = await completer.future;

      expect(completer.isCompleted, isTrue);
      expect(event.type, ServerEventType.clientConnected);
      expect(event.message, contains('Client connected'));
    });

    test(
      'should handle handshake',
      () async {
        final completer = Completer<Message>();
        final documentId = PeerId.generate().id;

        final events = <ServerEvent>[];

        stubHttpServer(
          mockHttpServer: mockHttpServer,
          httpRequestController: httpRequestController,
        );
        stubWebSocket(
          mockWebSocketTransformer: mockWebSocketTransformer,
          serverSockets: mockWebSockets,
          clientSockets: <MockWebSocket>[],
          messagesSent: messagesSent,
        );

        await registry.addDocument(documentId);

        messagesSent.stream.listen((data) {
          final message = codec.decode(data);
          completer.complete(message);
        });
        server.serverEvents.listen(events.add);
        await server.start();

        httpRequestController.add(MockHttpRequest());
        final client = PeerId.generate();
        await Future<void>.delayed(Duration.zero);

        mockWebSockets.first.incomingController.add(
          codec.encode(
            HandshakeRequestMessage(
              author: client,
              documentId: documentId,
              versionVector: VersionVector({}),
            ),
          )!,
        );

        final message = await completer.future;

        expect(completer.isCompleted, isTrue);
        expect(message.type, MessageType.handshakeResponse);
        expect(message.documentId, documentId);
        expect(message, isA<HandshakeResponseMessage>());

        await Future<void>.delayed(Duration.zero);

        final handshakeMessage = events.last;
        expect(
          handshakeMessage.message,
          contains('handshake completed:'),
        );
      },
    );

    test('should handle multiple clients', () async {
      final documentId = PeerId.generate().id;
      final client1 = PeerId.generate();
      final client2 = PeerId.generate();

      final completer = Completer<bool>();
      final serverMessages = <Message>[];
      final serverEvents = <ServerEvent>[];

      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: mockWebSockets,
        clientSockets: <MockWebSocket>[],
        messagesSent: messagesSent,
      );

      await registry.addDocument(documentId);

      messagesSent.stream.listen((data) {
        final message = codec.decode(data);
        serverMessages.add(message!);

        if (serverMessages.length == 2) {
          completer.complete(true);
        }
      });
      server.serverEvents.listen(serverEvents.add);
      await server.start();

      // Client 1
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSockets[0].incomingController.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client1,
                documentId: documentId,
                versionVector: VersionVector({}),
              ),
            )!,
          );

      // Client 2
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSockets[1].incomingController.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client2,
                documentId: documentId,
                versionVector: VersionVector({}),
              ),
            )!,
          );

      await completer.future;
      await Future<void>.delayed(Duration.zero);

      expect(serverMessages.length, 2);
      expect(serverEvents.length, 5);

      expect(serverMessages[0].type, MessageType.handshakeResponse);
      expect(serverMessages[1].type, MessageType.handshakeResponse);

      expect(
        serverEvents
            .where((event) => event.type == ServerEventType.clientConnected),
        hasLength(2),
      );

      expect(
        serverEvents
            .where((event) => event.type == ServerEventType.clientHandshake),
        hasLength(2),
      );
    });

    Future<_ServerSetup> setupServer({
      void Function(Message)? onMessage,
      void Function(ServerEvent)? onEvent,
    }) async {
      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: mockWebSockets,
        clientSockets: <MockWebSocket>[],
        messagesSent: messagesSent,
      );

      final serverMessages = <Message>[];
      final serverEvents = <ServerEvent>[];

      messagesSent.stream.listen((data) {
        final message = codec.decode(data);
        serverMessages.add(message!);
        onMessage?.call(message);
      });
      server.serverEvents.listen((event) {
        serverEvents.add(event);
        onEvent?.call(event);
      });

      await server.start();

      return _ServerSetup(
        serverMessages: serverMessages,
        serverEvents: serverEvents,
      );
    }

    /// Adds a client to the server
    ///
    /// This will send a handshake request to the server
    /// and wait for the client to be added to the server
    Future<void> addClient({
      required String documentId,
      required MockWebSocket Function() mockWebSocket,
      PeerId? clientId,
    }) async {
      final client = clientId ?? PeerId.generate();

      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSocket().incomingController.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client,
                documentId: documentId,
                versionVector: VersionVector({}),
              ),
            )!,
          );
    }

    test('should handle incoming changes', () async {
      final documentId = PeerId.generate();
      final client1 = PeerId.generate();
      final client2 = PeerId.generate();

      // server doc
      final serverDoc = CRDTDocument(peerId: documentId);
      CRDTListHandler<String>(serverDoc, 'list');
      await registry.addDocument(documentId.id);

      // client doc
      final clientDoc = CRDTDocument(peerId: documentId);
      CRDTListHandler<String>(clientDoc, 'list').insert(0, 'Hello');
      final change = clientDoc.exportChanges().first;

      final completer = Completer<Message>();

      final setup = await setupServer(
        onMessage: (message) {
          if (message.type == MessageType.change) {
            completer.complete(message);
          }
        },
      );

      await addClient(
        documentId: documentId.id,
        clientId: client1,
        mockWebSocket: () => mockWebSockets[0],
      );
      await addClient(
        documentId: documentId.id,
        clientId: client2,
        mockWebSocket: () => mockWebSockets[1],
      );

      await Future<void>.delayed(Duration.zero);

      expect(setup.serverMessages.length, 2);
      expect(setup.serverEvents.length, 5);

      await Future<void>.delayed(Duration.zero);

      // client 1 sends change to server
      // server will broadcast the change to all clients (`client2`)
      mockWebSockets[0].incomingController.add(
            codec.encode(
              ChangeMessage(
                change: change,
                documentId: documentId.id,
              ),
            )!,
          );

      // wait for the change to be broadcasted to the other client
      final message = await completer.future;

      expect(setup.serverMessages.length, 3);
      // The change from client1 is applied on the server, which then broadcasts
      // it. (The exact event ordering relative to the completer is not pinned:
      // outbound sends are serialized through a queue, so the broadcast event
      // may settle before or after this point.)
      expect(
        setup.serverEvents
            .where((e) => e.type == ServerEventType.clientChangeApplied),
        hasLength(1),
      );

      // check the broadcasted message
      expect(message.type, setup.serverMessages[2].type);
      expect(message.documentId, documentId.id);
      expect(message, isA<ChangeMessage>());
      expect((message as ChangeMessage).change.id, change.id);
    });

    test(
      'should tell the client it is out of sync on a causally-not-ready change',
      () async {
        final documentId = PeerId.generate().id;
        await registry.addDocument(documentId);

        // Build two causally dependent changes; only the second is sent to the
        // server, whose document has neither — so it is not causally ready.
        final authorDoc = CRDTDocument(peerId: PeerId.generate());
        CRDTListHandler<String>(authorDoc, 'list')
          ..insert(0, 'a')
          ..insert(1, 'b');
        final orphanChange = authorDoc.exportChanges()[1];

        final setup = await setupServer();
        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[0],
        );
        await Future<void>.delayed(Duration.zero);

        mockWebSockets[0].incomingController.add(
              codec.encode(
                ChangeMessage(
                  change: orphanChange,
                  documentId: documentId,
                ),
              )!,
            );
        await Future<void>.delayed(Duration.zero);

        // Regression: the registry used to swallow CausallyNotReadyException
        // and return false, so the server never emitted OUT_OF_SYNC and the
        // client never re-synced.
        final outOfSyncErrors = setup.serverMessages
            .whereType<ErrorMessage>()
            .where((m) => m.code == Protocol.errorOutOfSync)
            .toList();
        expect(outOfSyncErrors, hasLength(1));

        expect(
          setup.serverEvents
              .where((e) => e.type == ServerEventType.clientOutOfSync),
          hasLength(1),
        );
      },
    );

    /// Applies a single change to the registry document so the server has a
    /// non-empty state, and returns the resulting server version vector.
    Future<VersionVector> seedServerChange(String documentId) async {
      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(authorDoc, 'list').insert(0, 'a');
      final change = authorDoc.exportChanges().first;
      await registry.applyChange(documentId, change);
      return (await registry.getDocument(documentId))!.getVersionVector();
    }

    test(
      'should snapshot and prune once every client confirms the state',
      () async {
        final documentId = PeerId.generate().id;
        await registry.addDocument(documentId);
        final serverVV = await seedServerChange(documentId);

        final setup = await setupServer();
        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[0],
        );
        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[1],
        );
        await Future<void>.delayed(Duration.zero);

        // Clients reported an empty version vector at handshake -> not aligned.
        expect(await registry.getLatestSnapshot(documentId), isNull);

        // Both clients now report the server's version vector via ping.
        for (final index in [0, 1]) {
          mockWebSockets[index].incomingController.add(
                codec.encode(
                  PingMessage(
                    documentId: documentId,
                    timestamp: 0,
                    versionVector: serverVV,
                  ),
                )!,
              );
          await Future<void>.delayed(Duration.zero);
        }

        expect(await registry.getLatestSnapshot(documentId), isA<Snapshot>());
        expect(
          setup.serverEvents
              .where((e) => e.type == ServerEventType.snapshotCreated),
          hasLength(1),
        );
      },
    );

    test('should not snapshot while a client is behind', () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      final serverVV = await seedServerChange(documentId);

      final setup = await setupServer();
      await addClient(
        documentId: documentId,
        mockWebSocket: () => mockWebSockets[0],
      );
      await addClient(
        documentId: documentId,
        mockWebSocket: () => mockWebSockets[1],
      );
      await Future<void>.delayed(Duration.zero);

      // Only the first client is aligned; the second stays behind (empty).
      mockWebSockets[0].incomingController.add(
            codec.encode(
              PingMessage(
                documentId: documentId,
                timestamp: 0,
                versionVector: serverVV,
              ),
            )!,
          );
      mockWebSockets[1].incomingController.add(
            codec.encode(
              PingMessage(
                documentId: documentId,
                timestamp: 0,
                versionVector: VersionVector({}),
              ),
            )!,
          );
      await Future<void>.delayed(Duration.zero);

      expect(await registry.getLatestSnapshot(documentId), isNull);
      expect(
        setup.serverEvents
            .where((e) => e.type == ServerEventType.snapshotCreated),
        isEmpty,
      );
    });

    test('should close every client session on stop', () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      await setupServer();

      await addClient(
        documentId: documentId,
        mockWebSocket: () => mockWebSockets[0],
      );
      await addClient(
        documentId: documentId,
        mockWebSocket: () => mockWebSockets[1],
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockWebSockets, hasLength(2));

      await server.stop();

      // Regression: `stop()` used to pass the `session.close` tear-off without
      // calling it, so the underlying sockets were never closed.
      verify(() => mockWebSockets[0].close(any(), any())).called(1);
      verify(() => mockWebSockets[1].close(any(), any())).called(1);
    });

    test(
      'should broadcast to healthy clients even when one client send fails',
      () async {
        final documentId = PeerId.generate().id;
        await registry.addDocument(documentId);

        // Build a change to broadcast.
        final clientDoc = CRDTDocument(peerId: PeerId.generate());
        CRDTListHandler<String>(clientDoc, 'list').insert(0, 'Hi');
        final change = clientDoc.exportChanges().first;

        final setup = await setupServer();

        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[0],
        );
        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[1],
        );
        await addClient(
          documentId: documentId,
          mockWebSocket: () => mockWebSockets[2],
        );
        await Future<void>.delayed(Duration.zero);

        // Make the first session's socket fail on every send.
        when(() => mockWebSockets[0].add(any<List<int>>()))
            .thenThrow(Exception('dead socket'));

        // Regression: a failing first client used to abort the whole
        // broadcast, so the healthy clients never received the message.
        await expectLater(
          server.broadcastMessage(
            Message.change(documentId: documentId, change: change),
          ),
          completes,
        );
        await Future<void>.delayed(Duration.zero);

        final changeMessages = setup.serverMessages
            .where((m) => m.type == MessageType.change)
            .toList();
        // The two healthy clients each received the broadcast.
        expect(changeMessages, hasLength(2));
      },
    );
  });
}

/// Internal class used to setup the server for testing
///
/// This contains the messages sent from the server to the clients
/// and the events emitted by the server
class _ServerSetup {
  _ServerSetup({
    required this.serverMessages,
    required this.serverEvents,
  });

  /// Messages sent from the server to the clients
  final List<Message> serverMessages;

  /// Events emitted by the server
  final List<ServerEvent> serverEvents;
}
