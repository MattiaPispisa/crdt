// ignore_for_file: avoid_redundant_argument_values - explicit test setup

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:test/test.dart';
import 'utils/awareness.dart';
import 'utils/stub.dart';

void main() {
  /// This test verifies that the client and server
  /// can communicate with each other
  /// and is used to validate the infrastructure before the next group.
  ///
  /// The next group assumes communication works
  /// and focuses solely on message exchange logic.
  group('WebSocket Integration Tests', () {
    test(
        'should setup a communication between '
        'the client and the server', () async {
      const documentId = 'test-document-1';
      final clientPeerId = PeerId.generate();

      final codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: Message.fromJson,
      );

      const port = 8080;
      final httpServer = MockHttpServer();
      final httpRequestController = StreamController<HttpRequest>.broadcast();
      final registry = InMemoryCRDTServerRegistry();
      final mockWebSocketTransformer = MockWebSocketTransformer();
      final outgoingServerSockets = <MockWebSocket>[];
      final incomingServerSocket = <MockWebSocket>[];

      final serverMessagesSentController =
          StreamController<List<int>>.broadcast();
      final clientMessagesSentController =
          StreamController<List<int>>.broadcast();

      final serverMessagesSent = <Message>[];
      final clientMessagesSent = <Message>[];

      serverMessagesSentController.stream.listen((data) {
        final message = codec.decode(data);
        if (message != null) {
          serverMessagesSent.add(message);
        }
      });
      clientMessagesSentController.stream.listen((data) {
        final message = codec.decode(data);
        if (message != null) {
          clientMessagesSent.add(message);
        }
      });

      // Setup stubs
      stubHttpServer(
        mockHttpServer: httpServer,
        httpRequestController: httpRequestController,
        port: port,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: outgoingServerSockets,
        clientSockets: incomingServerSocket,
        messagesSent: serverMessagesSentController,
      );

      // Create server with WebSocketServer.test
      final server = WebSocketServer.test(
        serverFactory: () async => httpServer,
        serverRegistry: registry,
        serverTransformer: mockWebSocketTransformer,
      );

      await registry.addDocument(documentId);
      final registryDoc = (await registry.getDocument(documentId))!;
      CRDTListHandler<String>(registryDoc, 'test-list');

      await server.start();

      final webSocketCount = outgoingServerSockets.length;

      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);

      expect(
        outgoingServerSockets.length,
        webSocketCount + 1,
        reason: 'After upgrade request, the number of web sockets '
            'should be incremented by 1',
      );

      final clientDoc =
          CRDTDocument(peerId: clientPeerId, documentId: documentId);

      final client = WebSocketClient.test(
        url: 'ws://localhost:$port',
        document: clientDoc,
        author: clientPeerId,
        transportFactory: () => Transport.create(
          MockTransportConnector(
            incoming: outgoingServerSockets.last,
            outgoing: incomingServerSocket.last,
            messagesSent: clientMessagesSentController,
          ),
        ),
        messageCodec: codec,
      );

      expect(client.sessionId, isNull);

      final clientConnected = await client.connect();
      expect(clientConnected, isTrue);
      expect(client.sessionId, isNotNull);

      await Future<void>.delayed(Duration.zero);

      // Verify handshake messages were exchanged
      final handshakeRequests = clientMessagesSent
          .where((m) => m.type == MessageType.handshakeRequest)
          .toList();
      final handshakeResponses = serverMessagesSent
          .where((m) => m.type == MessageType.handshakeResponse)
          .toList();

      expect(
        handshakeRequests.length,
        1,
        reason: 'Client should send handshake request',
      );
      expect(
        handshakeResponses.length,
        1,
        reason: 'Server should respond to handshake request',
      );

      // Verify handshake request properties
      for (final request in handshakeRequests) {
        final handshakeRequest = request as HandshakeRequestMessage;
        expect(handshakeRequest.documentId, documentId);
        expect(handshakeRequest.versionVector, isNotNull);
      }

      // Verify handshake response properties
      for (final response in handshakeResponses) {
        final handshakeResponse = response as HandshakeResponseMessage;
        expect(handshakeResponse.documentId, documentId);
        expect(handshakeResponse.sessionId, isNotNull);
        expect(handshakeResponse.versionVector, isNotNull);
      }

      await expectLater(() async => client.disconnect(), returnsNormally);
      expect(client.dispose, returnsNormally);
      await expectLater(() async => server.dispose(), returnsNormally);

      await Future<void>.delayed(Duration.zero);

      expect(client.connectionStatusValue, ConnectionStatus.disconnected);
      expect(client.sessionId, isNull);
    });
  });

  group(
      'WebSocket integration test -'
      ' already connected', () {
    // document
    const documentId = 'd77712cf-ec51-4448-bc2e-bd8e6d72d741';
    const todoList = 'todo-list';

    // http
    const port = 8080;
    late StreamController<HttpRequest> httpRequestController;
    late MockHttpServer mockHttpServer;
    late MockWebSocketTransformer mockWebSocketTransformer;

    // registry
    late InMemoryCRDTServerRegistry registry;

    // server
    late WebSocketServer server;
    late List<MockWebSocket> outgoingServerSockets;
    late List<MockWebSocket> incomingServerSockets;
    late StreamController<List<int>> serverMessagesSentController;
    late List<Message> serverMessagesSent;
    late CRDTListHandler<Map<String, dynamic>> serverTodoListHandler;
    late _TestPluginServer testPluginServer;
    // late ServerAwarenessPlugin serverAwarenessPlugin;

    // clients
    late WebSocketClient client1;
    late void Function(int) updateClient1SocketIndex;
    late StreamController<List<int>> client1MessagesSentController;
    late List<Message> client1MessagesSent;
    late CRDTListHandler<Map<String, dynamic>> client1TodoListHandler;
    late _TestPluginClient testPluginClient1;
    // late ClientAwarenessPlugin awarenessPluginClient1;

    late WebSocketClient client2;
    late StreamController<List<int>> client2MessagesSentController;
    late List<Message> client2MessagesSent;
    late CRDTListHandler<Map<String, dynamic>> client2TodoListHandler;
    late _TestPluginClient testPluginClient2;
    // late ClientAwarenessPlugin awarenessPluginClient2;

    Future<void> waitForClient1Status(ConnectionStatus expectedStatus) {
      return client1.connectionStatus
          .firstWhere((status) => status == expectedStatus);
    }

    /// Add a client connection to the server
    /// (send an "upgrade request" to the server)
    Future<void> addClientConnection() async {
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      return;
    }

    /// Setup a client and connect it to the server
    /// (send an "upgrade request" to the server)
    ///
    /// The client will have a dynamic transport factory that allows
    /// reconnection with new sockets when [connect] is called again.
    ///
    /// Returns a [_ClientSetup] with:
    /// - client: the WebSocketClient instance
    /// - updateSocketIndex: a function to update which socket the client uses
    Future<_ClientSetup> setupClient({
      required int clientCount,
      required PeerId peerId,
      required StreamController<List<int>> messagesSentController,
      required JsonMessageCodec<Message> codec,
      required List<ClientSyncPlugin> clientPlugins,
    }) async {
      final webSocketCount = outgoingServerSockets.length;

      await addClientConnection();

      expect(
        outgoingServerSockets.length,
        webSocketCount + 1,
        reason: 'After upgrade request, the number of web sockets '
            'should be incremented by 1',
      );

      final clientDoc = CRDTDocument(
        peerId: peerId,
        documentId: documentId,
      );

      // Track which socket index this client should use
      // Initially it's the socket that was just created
      var currentSocketIndex = clientCount - 1;

      final client = WebSocketClient.test(
        url: 'ws://localhost:$port',
        document: clientDoc,
        author: peerId,
        plugins: clientPlugins,
        transportFactory: () {
          // Dynamic transport factory that allows reconnection:
          // When connect() is called after a disconnection,
          // this will use the current socket index which can be updated
          return Transport.create(
            MockTransportConnector(
              incoming: outgoingServerSockets[currentSocketIndex],
              outgoing: incomingServerSockets[currentSocketIndex],
              messagesSent: messagesSentController,
            ),
          );
        },
        messageCodec: codec,
      );

      final clientConnected = await client.connect();
      expect(clientConnected, isTrue);

      // Return both the client and a function to update the socket index
      return _ClientSetup(
        client,
        (int newIndex) => currentSocketIndex = newIndex,
      );
    }

    List<_Todo> getTodoList(CRDTListHandler<Map<String, dynamic>> listHandler) {
      return listHandler.value.map(_Todo.fromJson).toList();
    }

    /// expect equals:
    /// - [client1TodoListHandler]
    /// - [client2TodoListHandler]
    /// - [serverTodoListHandler]
    ///
    /// if a list is provided it's also compered
    void expectSameList({List<_Todo>? list}) {
      expect(
        getTodoList(client1TodoListHandler),
        orderedEquals(getTodoList(client2TodoListHandler)),
        reason: 'client1 and client2 should have the same list',
      );
      expect(
        getTodoList(client1TodoListHandler),
        orderedEquals(getTodoList(serverTodoListHandler)),
        reason: 'client1 and server should have the same list',
      );
      if (list != null) {
        expect(
          getTodoList(client1TodoListHandler),
          orderedEquals(list),
          reason: 'client1 should have the same list as the provided list',
        );
      }
    }

    /// expect clients has same changes between each others
    /// and the changes length is `count`
    void expectSameChanges(int count) {
      final client1Changes = client1.document.exportChanges();
      expect(
        client1Changes.map((c) => c.id),
        orderedEquals(client2.document.exportChanges().map((c) => c.id)),
      );
      expect(client1Changes, hasLength(count));
    }

    group('should handle communication between clients', () {
      setUp(() async {
        httpRequestController = StreamController<HttpRequest>.broadcast();
        mockWebSocketTransformer = MockWebSocketTransformer();

        outgoingServerSockets = [];
        incomingServerSockets = [];

        final codec = JsonMessageCodec<Message>(
          toJson: (message) => message.toJson(),
          fromJson: Message.fromJson,
        );

        void listenToMessages(
          StreamController<List<int>> messagesSent,
          List<Message> messages,
        ) {
          messagesSent.stream.listen((data) {
            final message = codec.decode(data);
            if (message != null) {
              messages.add(message);
            }
          });
        }

        serverMessagesSentController = StreamController<List<int>>.broadcast();
        serverMessagesSent = [];
        listenToMessages(serverMessagesSentController, serverMessagesSent);

        final client1PeerId = PeerId.generate();
        client1MessagesSentController = StreamController<List<int>>.broadcast();
        client1MessagesSent = [];
        listenToMessages(client1MessagesSentController, client1MessagesSent);

        final client2PeerId = PeerId.generate();
        client2MessagesSentController = StreamController<List<int>>.broadcast();
        client2MessagesSent = [];
        listenToMessages(client2MessagesSentController, client2MessagesSent);

        mockHttpServer = MockHttpServer();
        registry = InMemoryCRDTServerRegistry();

        // Setup stubs
        stubHttpServer(
          mockHttpServer: mockHttpServer,
          httpRequestController: httpRequestController,
          port: port,
        );
        stubWebSocket(
          mockWebSocketTransformer: mockWebSocketTransformer,
          serverSockets: outgoingServerSockets,
          clientSockets: incomingServerSockets,
          messagesSent: serverMessagesSentController,
        );

        // Create server with WebSocketServer.test
        testPluginServer = _TestPluginServer();
        // serverAwarenessPlugin = ServerAwarenessPlugin();
        server = WebSocketServer.test(
          serverFactory: () async => mockHttpServer,
          serverRegistry: registry,
          serverTransformer: mockWebSocketTransformer,
          plugins: [
            testPluginServer,
            // serverAwarenessPlugin,
          ],
        );

        await registry.addDocument(documentId);
        final registryDoc = (await registry.getDocument(documentId))!;
        serverTodoListHandler = CRDTListHandler(registryDoc, todoList);

        await server.start();

        testPluginClient1 = _TestPluginClient();
        // awarenessPluginClient1 = ClientAwarenessPlugin();
        final client1Setup = await setupClient(
          clientCount: 1,
          peerId: client1PeerId,
          messagesSentController: client1MessagesSentController,
          codec: codec,
          clientPlugins: [
            testPluginClient1,
            // awarenessPluginClient1,
          ],
        );
        client1 = client1Setup.client;
        updateClient1SocketIndex = client1Setup.updateSocketIndex;
        client1TodoListHandler = CRDTListHandler(client1.document, todoList);

        await Future<void>.delayed(Duration.zero);

        testPluginClient2 = _TestPluginClient();
        // awarenessPluginClient2 = ClientAwarenessPlugin();
        client2 = (await setupClient(
          clientCount: 2,
          peerId: client2PeerId,
          messagesSentController: client2MessagesSentController,
          codec: codec,
          clientPlugins: [
            testPluginClient2,
            // awarenessPluginClient2,
          ],
        ))
            .client;
        client2TodoListHandler = CRDTListHandler(client2.document, todoList);

        await Future<void>.delayed(Duration.zero);

        // await handshake messages to be exchanged
        // Verify handshake messages were exchanged
        final handshakeClient1Requests = client1MessagesSent
            .where((m) => m.type == MessageType.handshakeRequest)
            .toList();
        final handshakeClient2Requests = client2MessagesSent
            .where((m) => m.type == MessageType.handshakeRequest)
            .toList();
        final handshakeServerResponses = serverMessagesSent
            .where((m) => m.type == MessageType.handshakeResponse)
            .toList();

        expect(handshakeClient1Requests.length, 1);
        expect(handshakeClient2Requests.length, 1);
        expect(handshakeServerResponses.length, 2);
      });

      tearDown(() async {
        client1.dispose();
        client2.dispose();

        await server.stop();

        await registry.clear();
      });

      test('should handle communication between clients', () async {
        client1TodoListHandler.insert(
          0,
          const _Todo(text: 'Buy milk').toJson(),
        );
        await Future<void>.delayed(Duration.zero);

        final client1Changes = client1MessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();
        expect(client1Changes.length, 1);

        final serverChanges = serverMessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();
        expect(
          serverChanges.length,
          1,
          reason: 'Server should broadcast the change to all clients'
              ' except source message client (client1)',
        );

        final client2Changes = client2MessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();
        expect(
          client2Changes.length,
          1,
          reason: 'broadcasted change to client2',
        );

        expectSameList();
        expectSameChanges(1);
      });

      test('should be synced server and clients after a snapshot', () async {
        client1TodoListHandler
          ..insert(0, const _Todo(text: 'Buy milk').toJson())
          ..insert(1, const _Todo(text: 'Buy apples').toJson());

        await Future<void>.delayed(Duration.zero);

        client2TodoListHandler
          ..insert(2, const _Todo(text: 'Buy cheese').toJson())
          ..insert(3, const _Todo(text: 'Buy bread').toJson());

        await Future<void>.delayed(Duration.zero);

        expectSameList();

        final snap = await registry.createSnapshot(documentId);
        final doc = (await registry.getDocument(documentId))!;
        final changes = doc.exportChanges();

        await server.broadcastMessage(
          Message.documentStatus(
            documentId: documentId,
            snapshot: snap,
            changes: changes,
            versionVector: doc.getVersionVector(),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        expectSameList();
        expectSameChanges(0);
      });

      test('should handshake when sync problems occurs', () async {
        outgoingServerSockets.first.simulateError();

        await waitForClient1Status(ConnectionStatus.reconnecting);
        await waitForClient1Status(ConnectionStatus.connected);

        await Future<void>.delayed(Duration.zero);

        // After reconnection, handshake should be sent
        final client1Handshake = client1MessagesSent
            .where((m) => m.type == MessageType.handshakeRequest)
            .toList();
        expect(
          client1Handshake.length,
          2,
          reason: 'a handshake request should be sent after sync problems',
        );
        final serverHandshake = serverMessagesSent
            .where((m) => m.type == MessageType.handshakeResponse)
            .toList();
        expect(
          serverHandshake.length,
          3,
          reason: 'one handshake per client and one'
              ' after sync problems with client1',
        );
      });

      test('should send changes when sync problems occurs', () async {
        // add error to client1 socket
        outgoingServerSockets.first.simulateError();

        await waitForClient1Status(ConnectionStatus.reconnecting);

        // client1 makes changes during sync problems
        // (none is sent to the server)
        client1TodoListHandler
          ..insert(0, const _Todo(text: 'Buy milk').toJson())
          ..insert(1, const _Todo(text: 'Buy apples').toJson());

        var client1Changes = client1MessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();
        var serverChanges = serverMessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();

        expect(
          client1MessagesSent,
          orderedEquals([isA<HandshakeRequestMessage>()]),
          reason: 'client1 should not send changes when sync problems occurs',
        );
        expect(serverChanges.length, 0);

        await waitForClient1Status(ConnectionStatus.connected);

        // wait client 1 messages after reconnection
        await Future<void>.delayed(Duration.zero);

        // After reconnection, changes should be sent
        client1Changes = client1MessagesSent
            .where((m) => m.type == MessageType.changes)
            .toList();

        expect(
          client1Changes.length,
          1,
          reason: 'after sync problems the client send the changes'
              ' not available on the server',
        );
        serverChanges = serverMessagesSent
            .where((m) => m.type == MessageType.change)
            .toList();
        expect(serverChanges.length, 2);

        expectSameList(
          list: const [
            _Todo(text: 'Buy milk'),
            _Todo(text: 'Buy apples'),
          ],
        );
      });

      test(
          'should align clients - '
          'client1 after sync problems should import client2 changes',
          () async {
        // add error to client1 socket
        outgoingServerSockets.first.simulateError();

        await waitForClient1Status(ConnectionStatus.reconnecting);

        client1TodoListHandler
          ..insert(0, const _Todo(text: 'Buy milk').toJson())
          ..insert(1, const _Todo(text: 'Buy apples').toJson());

        await waitForClient1Status(ConnectionStatus.connected);

        await Future<void>.delayed(Duration.zero);

        expectSameList(
          list: const [
            _Todo(text: 'Buy milk'),
            _Todo(text: 'Buy apples'),
          ],
        );
      });

      test(
          'should align clients - '
          'client1 after sync problems should import client2 changes '
          'and send it unsent changes to the server', () async {
        // add error to client1 socket
        outgoingServerSockets.first.simulateError();

        await waitForClient1Status(ConnectionStatus.reconnecting);

        // client1 makes changes during sync problems
        // (none is sent to the server)
        client1TodoListHandler
          ..insert(0, const _Todo(text: 'Buy milk').toJson())
          ..insert(1, const _Todo(text: 'Buy apples').toJson());

        // client2 make changes and sent them to the server
        client2TodoListHandler
          ..insert(0, const _Todo(text: 'Buy bread').toJson())
          ..insert(1, const _Todo(text: 'Buy cheese').toJson());

        await waitForClient1Status(ConnectionStatus.connected);

        await Future<void>.delayed(Duration.zero);

        expectSameList();
      });

      test(
          'should align clients -'
          ' client1 after sync occurs must align also with a server snapshot',
          () async {
        // add error to client1 socket
        outgoingServerSockets.first.simulateError();

        await waitForClient1Status(ConnectionStatus.reconnecting);

        // client1 makes changes during sync problems
        // (none is sent to the server)
        client1TodoListHandler
          ..insert(0, const _Todo(text: 'Buy milk').toJson())
          ..insert(1, const _Todo(text: 'Buy apples').toJson());

        // client2 make changes and sent them to the server
        client2TodoListHandler
          ..insert(0, const _Todo(text: 'Buy bread').toJson())
          ..insert(1, const _Todo(text: 'Buy cheese').toJson());

        await Future<void>.delayed(Duration.zero);

        // ensure server has client2 changes
        expect(
          getTodoList(serverTodoListHandler),
          orderedEquals(const [
            _Todo(text: 'Buy bread'),
            _Todo(text: 'Buy cheese'),
          ]),
        );

        // create a server snapshot and broadcast it to clients
        final snapshot = await registry.createSnapshot(documentId);
        final document = (await registry.getDocument(documentId))!;
        final changes = document.exportChanges();

        await server.broadcastMessage(
          Message.documentStatus(
            documentId: documentId,
            versionVector: document.getVersionVector(),
            changes: changes,
            snapshot: snapshot,
          ),
        );

        await Future<void>.delayed(Duration.zero);

        // ensure status correctness
        expect(
          serverMessagesSent,
          contains(
            isA<DocumentStatusMessage>()
                .having((d) => d.changes?.length, 'length', 0)
                .having(
                  (d) => d.snapshot,
                  'snapshot',
                  isA<Snapshot>(),
                ),
          ),
        );

        // with snapshot client2 prune its changes
        expect(
          client2.document.exportChanges().length,
          0,
        );
        // client1 has sync problems,
        // so it has its changes not available on the server
        expect(
          client1.document.exportChanges().length,
          2,
        );

        await waitForClient1Status(ConnectionStatus.connected);

        await Future<void>.delayed(Duration.zero);

        expect(
          getTodoList(client1TodoListHandler),
          containsAll(const [
            _Todo(text: 'Buy milk'),
            _Todo(text: 'Buy apples'),
            _Todo(text: 'Buy bread'),
            _Todo(text: 'Buy cheese'),
          ]),
        );
        expectSameList();

        // client1 changes received from server after the snapshot
        expect(client2.document.exportChanges().length, 2);
        expect(client1.document.exportChanges().length, 2);
      });

      test('should handle explicit client disconnection', () async {
        expect(client1.connectionStatusValue, ConnectionStatus.connected);
        expect(client1.sessionId, isNotNull);

        // Explicitly disconnect the client
        unawaited(client1.disconnect());

        await waitForClient1Status(ConnectionStatus.disconnected);

        expect(client1.connectionStatusValue, ConnectionStatus.disconnected);
        expect(client1.sessionId, isNull);
      });

      test(
        'should handle simulated disconnection and reconnect with new session',
        () async {
          // Use client1 which already has dynamic transport factory
          // Store initial session ID
          final initialSessionId = client1.sessionId!;
          expect(initialSessionId, isNotNull);
          expect(client1.connectionStatusValue, ConnectionStatus.connected);

          // Simulate a permanent client1 disconnection
          outgoingServerSockets.first.simulateDisconnection();

          // Wait for the client to detect disconnection and try to reconnect
          await Future<void>.delayed(Duration.zero);

          // Wait for error state after reconnection attempts fail
          // This may take several seconds (5 attempts * 1 second interval)
          await waitForClient1Status(ConnectionStatus.error);

          expect(client1.connectionStatusValue, ConnectionStatus.error);

          // Simulate a new HTTP upgrade request for reconnection
          final socketCountBefore = outgoingServerSockets.length;
          await addClientConnection();

          // Verify that a new socket was created on the server
          expect(
            outgoingServerSockets.length,
            socketCountBefore + 1,
            reason: 'A new socket should be created for the reconnection',
          );

          // Update client1 to use the new socket
          final newSocketIndex = outgoingServerSockets.length - 1;
          updateClient1SocketIndex(newSocketIndex);

          expect(
            serverMessagesSent,
            isNot(contains(isA<DocumentStatusMessage>())),
          );

          // Client1 reconnects - this will call transportFactory again
          // which will now use the new socket
          final reconnected = await client1.connect();
          expect(reconnected, isTrue);

          // Verify new session was created
          expect(client1.connectionStatusValue, ConnectionStatus.connected);
          expect(client1.sessionId, isNotNull);
          expect(
            client1.sessionId,
            isNot(equals(initialSessionId)),
            reason: 'A new sessionId should be assigned after reconnection',
          );

          await Future<void>.delayed(Duration.zero);
          expect(
            serverMessagesSent,
            isNot(contains(isA<DocumentStatusMessage>())),
            reason: 'No reason to request a document status after reconnection',
          );
        },
      );

      test('should client1 from error state to connected', () async {
        outgoingServerSockets.first.simulateDisconnection();
        await Future<void>.delayed(Duration.zero);
        await waitForClient1Status(ConnectionStatus.error);
        // now client1 should be in error

        client2TodoListHandler
          ..insert(
            0,
            const _Todo(text: 'Buy bread').toJson(),
          )
          ..insert(
            1,
            const _Todo(text: 'Buy milk').toJson(),
          );

        await Future<void>.delayed(Duration.zero);

        var serverDoc = (await registry.getDocument(documentId))!;

        // server is sync with client2, client1 is in error
        expect(client1.document.exportChanges().length, 0);
        expect(client2.document.exportChanges().length, 2);
        expect(serverDoc.exportChanges().length, 2);

        // client1 makes changes during sync problems
        // (none is sent to the server)
        client1TodoListHandler.insert(
          0,
          const _Todo(text: 'Buy cheese').toJson(),
        );

        await Future<void>.delayed(Duration.zero);

        expect(client1.document.exportChanges().length, 1);
        expect(client2.document.exportChanges().length, 2);
        expect(serverDoc.exportChanges().length, 2);

        // take a snapshot of the server and broadcast it to clients
        final snap = await registry.createSnapshot(documentId);
        serverDoc = (await registry.getDocument(documentId))!;

        await server.broadcastMessage(
          Message.documentStatus(
            documentId: documentId,
            snapshot: snap,
            changes: serverDoc.exportChanges(),
            versionVector: serverDoc.getVersionVector(),
          ),
        );

        await Future<void>.delayed(Duration.zero);

        expect(client1.document.exportChanges().length, 1);
        expect(client2.document.exportChanges().length, 0);
        expect(serverDoc.exportChanges().length, 0);

        // reconnect client1
        await addClientConnection();
        updateClient1SocketIndex(
          outgoingServerSockets.length - 1,
        ); // last socket
        unawaited(client1.connect());
        await waitForClient1Status(ConnectionStatus.connected);

        await Future<void>.delayed(Duration.zero);

        // now client1 should be sync with server and client2
        expect(client1.document.exportChanges().length, 1);
        expect(client2.document.exportChanges().length, 1);
        expect(serverDoc.exportChanges().length, 1);
        expectSameList();
      });

      test('should send message to client', () async {
        final clientId = client1.sessionId!;
        final timestamp = DateTime(1997, 11, 12).millisecondsSinceEpoch;

        final initialPongCount =
            serverMessagesSent.where((m) => m.type == MessageType.pong).length;

        await server.sendMessageToClient(
          clientId,
          Message.pong(
            documentId: documentId,
            originalTimestamp: timestamp,
            responseTimestamp: timestamp,
          ),
        );

        await Future<void>.delayed(Duration.zero);

        final pongCount =
            serverMessagesSent.where((m) => m.type == MessageType.pong).length;
        expect(pongCount, initialPongCount + 1);
      });

      group('plugins system', () {
        test('should setup plugins correctly', () {
          expect(testPluginServer.sessionDocumentRegisteredCount, 2);
          expect(testPluginServer.sessionNewSessionCount, 2);

          expect(testPluginClient1.connectedCount, 1);
          expect(testPluginClient2.connectedCount, 1);

          expect(testPluginServer.sessionMessageCount, 0);
          expect(testPluginClient1.messageCount, 0);
          expect(testPluginClient2.messageCount, 0);
        });

        test('should communicate with plugins', () async {
          await testPluginServer.sendCount(documentId);

          await Future<void>.delayed(Duration.zero);

          expect(testPluginClient1.count, equals(1));
          expect(testPluginClient2.count, equals(1));

          await testPluginClient1.sendCount();

          await Future<void>.delayed(Duration.zero);

          expect(testPluginServer.count, equals(2));
        });

        test('should dispose plugins correctly', () async {
          await client1.disconnect();
          await client2.disconnect();
          client1.dispose();
          client2.dispose();

          await server.dispose();

          expect(testPluginServer.disposeCount, equals(1));
          expect(testPluginClient1.disposeCount, equals(1));
          expect(testPluginClient2.disposeCount, equals(1));
        });
      });
    });

    group('awareness plugin', () {
      late ClientAwarenessPlugin client1AwarenessPlugin;
      late ClientAwarenessPlugin client2AwarenessPlugin;
      late ServerAwarenessPlugin serverAwarenessPlugin;

      setUp(() async {
        httpRequestController = StreamController<HttpRequest>.broadcast();
        mockWebSocketTransformer = MockWebSocketTransformer();

        outgoingServerSockets = [];
        incomingServerSockets = [];

        final codec = JsonMessageCodec<Message>(
          toJson: (message) => message.toJson(),
          fromJson: Message.fromJson,
        );

        void listenToMessages(
          StreamController<List<int>> messagesSent,
          List<Message> messages,
        ) {
          messagesSent.stream.listen((data) {
            final message = codec.decode(data);
            if (message != null) {
              messages.add(message);
            }
          });
        }

        serverMessagesSentController = StreamController<List<int>>.broadcast();
        serverMessagesSent = [];
        listenToMessages(serverMessagesSentController, serverMessagesSent);

        final client1PeerId = PeerId.generate();
        client1MessagesSentController = StreamController<List<int>>.broadcast();
        client1MessagesSent = [];
        listenToMessages(client1MessagesSentController, client1MessagesSent);

        final client2PeerId = PeerId.generate();
        client2MessagesSentController = StreamController<List<int>>.broadcast();
        client2MessagesSent = [];
        listenToMessages(client2MessagesSentController, client2MessagesSent);

        mockHttpServer = MockHttpServer();
        registry = InMemoryCRDTServerRegistry();

        // Setup stubs
        stubHttpServer(
          mockHttpServer: mockHttpServer,
          httpRequestController: httpRequestController,
          port: port,
        );
        stubWebSocket(
          mockWebSocketTransformer: mockWebSocketTransformer,
          serverSockets: outgoingServerSockets,
          clientSockets: incomingServerSockets,
          messagesSent: serverMessagesSentController,
        );

        serverAwarenessPlugin = ServerAwarenessPlugin();
        server = WebSocketServer.test(
          serverFactory: () async => mockHttpServer,
          serverRegistry: registry,
          serverTransformer: mockWebSocketTransformer,
          plugins: [
            serverAwarenessPlugin,
          ],
        );

        await registry.addDocument(documentId);
        final registryDoc = (await registry.getDocument(documentId))!;
        serverTodoListHandler = CRDTListHandler(registryDoc, todoList);

        await server.start();

        client1AwarenessPlugin = ClientAwarenessPlugin(
          throttleDuration: const Duration(milliseconds: 10),
        );
        client1 = (await setupClient(
          clientCount: 1,
          peerId: client1PeerId,
          messagesSentController: client1MessagesSentController,
          codec: codec,
          clientPlugins: [
            client1AwarenessPlugin,
          ],
        ))
            .client;

        client1TodoListHandler = CRDTListHandler(client1.document, todoList);

        await Future<void>.delayed(Duration.zero);

        client2AwarenessPlugin = ClientAwarenessPlugin(
          throttleDuration: const Duration(milliseconds: 10),
        );
        client2 = (await setupClient(
          clientCount: 2,
          peerId: client2PeerId,
          messagesSentController: client2MessagesSentController,
          codec: codec,
          clientPlugins: [
            client2AwarenessPlugin,
          ],
        ))
            .client;
        client2TodoListHandler = CRDTListHandler(client2.document, todoList);

        await Future<void>.delayed(Duration.zero);
      });

      test('should communicate correctly', () async {
        // update client awareness
        client1AwarenessPlugin.updateLocalState({
          'positionX': 0,
          'positionY': 0,
        });
        await Future<void>.delayed(Duration.zero);

        final client1Id = client1.sessionId!;
        final client2Id = client2.sessionId!;

        var client1Awareness = ClientAwareness(
          clientId: client1Id,
          metadata: {
            'positionX': 0,
            'positionY': 0,
          },
        );
        expect(
          client1AwarenessPlugin.awareness.states[client1Id],
          ClientAwarenessMatcher(clientAwareness: client1Awareness),
        );
        expect(
          client2AwarenessPlugin.awareness.states[client1Id],
          ClientAwarenessMatcher(clientAwareness: client1Awareness),
        );

        expect(
          client1AwarenessPlugin.myState,
          ClientAwarenessMatcher(clientAwareness: client1Awareness),
        );
        expect(
          client2AwarenessPlugin.myState,
          ClientAwarenessMatcher(
            clientAwareness: ClientAwareness(
              clientId: client2Id,
              metadata: {},
            ),
          ),
        );

        // wait throttle duration
        await Future<void>.delayed(const Duration(milliseconds: 20));

        client1AwarenessPlugin.requestState(documentId);

        // wait throttle duration
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // update clients awareness after client1 throttle duration
        client2AwarenessPlugin.updateLocalState({
          'positionX': 1,
          'positionY': 1,
        });

        client1AwarenessPlugin.updateLocalState({
          'positionX': 10,
          'positionY': 10,
        });

        // wait throttle duration
        await Future<void>.delayed(const Duration(milliseconds: 20));

        client1Awareness = ClientAwareness(
          clientId: client1Id,
          metadata: {
            'positionX': 10,
            'positionY': 10,
          },
        );
        final client2Awareness = ClientAwareness(
          clientId: client2Id,
          metadata: {
            'positionX': 1,
            'positionY': 1,
          },
        );

        expect(
          client1AwarenessPlugin.myState,
          ClientAwarenessMatcher(
            clientAwareness: client1Awareness,
          ),
        );
        expect(
          client2AwarenessPlugin.myState,
          ClientAwarenessMatcher(clientAwareness: client2Awareness),
        );

        await Future<void>.delayed(Duration.zero);

        expect(
          client1AwarenessPlugin.awareness,
          DocumentAwarenessMatcher(
            documentAwareness: DocumentAwareness(
              documentId: documentId,
              states: {
                client1Id: client1Awareness,
                client2Id: client2Awareness,
              },
            ),
          ),
        );

        expect(
          client2AwarenessPlugin.awareness,
          DocumentAwarenessMatcher(
            documentAwareness: DocumentAwareness(
              documentId: documentId,
              states: {
                client1Id: client1Awareness,
                client2Id: client2Awareness,
              },
            ),
          ),
        );

        expect(
          () => client1AwarenessPlugin.dispose(),
          returnsNormally,
        );
        expect(
          () => serverAwarenessPlugin.dispose(),
          returnsNormally,
        );
      });
    });
  });
}

enum _TestPluginMessageType implements MessageTypeValue {
  testPluginMessage(100);

  const _TestPluginMessageType(this.value);

  @override
  final int value;
}

class _TestPluginClient extends ClientSyncPlugin {
  _TestPluginClient()
      : messageCodec = JsonMessageCodec<Message>(
          toJson: (message) => message.toJson(),
          fromJson: _TestPluginMessage.fromJson,
        );

  int disposeCount = 0;
  int connectedCount = 0;
  int disconnectedCount = 0;
  int messageCount = 0;

  int count = 0;

  @override
  void dispose() {
    disposeCount++;
    return;
  }

  Future<void> sendCount() async {
    await client.sendMessage(
      _TestPluginMessage(
        client.document.documentId,
        count: count + 1,
      ),
    );
  }

  @override
  final MessageCodec<Message> messageCodec;

  @override
  String get name => 'test-plugin';

  @override
  void onConnected() {
    connectedCount++;
    return;
  }

  @override
  void onDisconnected() {
    disconnectedCount++;
    return;
  }

  @override
  void onMessage(Message message) {
    if (message is _TestPluginMessage) {
      messageCount++;
      count = message.count;
    }

    return;
  }
}

class _TestPluginServer extends ServerSyncPlugin {
  _TestPluginServer()
      : messageCodec = JsonMessageCodec<Message>(
          toJson: (message) => message.toJson(),
          fromJson: _TestPluginMessage.fromJson,
        );

  int sessionClosedCount = 0;
  int sessionMessageCount = 0;
  int sessionNewSessionCount = 0;
  int sessionDocumentRegisteredCount = 0;
  int disposeCount = 0;

  int count = 0;

  @override
  void dispose() {
    disposeCount++;
    return;
  }

  @override
  final MessageCodec<Message> messageCodec;

  @override
  String get name => 'test-plugin';

  @override
  void onDocumentRegistered(ClientSession session, String documentId) {
    sessionDocumentRegisteredCount++;
  }

  Future<void> sendCount(String documentId) async {
    await server.broadcastMessage(
      _TestPluginMessage(
        documentId,
        count: count + 1,
      ),
    );
  }

  @override
  void onMessage(ClientSession session, Message message) {
    if (message is _TestPluginMessage) {
      sessionMessageCount++;
      count = message.count;
    }

    return;
  }

  @override
  void onNewSession(ClientSession session) {
    sessionNewSessionCount++;
    return;
  }

  @override
  void onSessionClosed(ClientSession session) {
    sessionClosedCount++;
    return;
  }
}

class _TestPluginMessage extends Message {
  const _TestPluginMessage(
    String documentId, {
    required this.count,
  }) : super(
          _TestPluginMessageType.testPluginMessage,
          documentId,
        );

  factory _TestPluginMessage.fromJson(Map<String, dynamic> json) {
    return _TestPluginMessage(
      json['documentId'] as String,
      count: json['count'] as int,
    );
  }

  final int count;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'count': count,
    };
  }
}

class _Todo {
  const _Todo({required this.text, this.isDone = false});

  factory _Todo.fromJson(Map<String, dynamic> json) {
    return _Todo(
      text: json['text'] as String,
      isDone: json['isDone'] as bool,
    );
  }

  final String text;
  final bool isDone;

  Map<String, dynamic> toJson() => {'text': text, 'isDone': isDone};

  @override
  String toString() {
    return 'Todo(text: $text, isDone: $isDone)';
  }

  _Todo copyWith({String? text, bool? isDone}) {
    return _Todo(
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is _Todo) {
      return text == other.text && isDone == other.isDone;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([text, isDone]);
}

/// Helper class to hold a client and its socket index updater
class _ClientSetup {
  _ClientSetup(this.client, this.updateSocketIndex);

  final WebSocketClient client;
  final void Function(int) updateSocketIndex;
}
