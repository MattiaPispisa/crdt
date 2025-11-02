// ignore_for_file: avoid_redundant_argument_values - explicit test setup

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:test/test.dart';

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

      final serverMessagesSent = StreamController<List<int>>.broadcast();
      final clientMessagesSent = StreamController<List<int>>.broadcast();

      final serverMessages = <Message>[];
      final clientMessages = <Message>[];

      serverMessagesSent.stream.listen((data) {
        final message = codec.decode(data);
        if (message != null) {
          serverMessages.add(message);
        }
      });
      clientMessagesSent.stream.listen((data) {
        final message = codec.decode(data);
        if (message != null) {
          clientMessages.add(message);
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
        messagesSent: serverMessagesSent,
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
            messagesSent: clientMessagesSent,
          ),
        ),
        messageCodec: codec,
      );

      final clientConnected = await client.connect();
      expect(clientConnected, isTrue);

      await Future<void>.delayed(Duration.zero);

      // Verify handshake messages were exchanged
      final handshakeRequests = clientMessages
          .where((m) => m.type == MessageType.handshakeRequest)
          .toList();
      final handshakeResponses = serverMessages
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
    });
  });

  group(
      'WebSocket integration test -'
      ' should handle communication between clients', () {
    // document
    const documentId = 'd77712cf-ec51-4448-bc2e-bd8e6d72d741';

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
    late List<Message> serverMessages;

    // clients
    late WebSocketClient client1;
    late StreamController<List<int>> client1MessagesSentController;
    late List<Message> client1Messages;

    late WebSocketClient client2;
    late StreamController<List<int>> client2MessagesSentController;
    late List<Message> client2Messages;

    /// Setup a client and connect it to the server
    /// (send an "upgrade request" to the server)
    ///
    /// Returns the client instance
    Future<WebSocketClient> setupClient({
      required PeerId peerId,
      required StreamController<List<int>> messagesSentController,
      required JsonMessageCodec<Message> codec,
    }) async {
      final webSocketCount = outgoingServerSockets.length;

      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);

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

      final client = WebSocketClient.test(
        url: 'ws://localhost:$port',
        document: clientDoc,
        author: peerId,
        transportFactory: () => Transport.create(
          MockTransportConnector(
            incoming: outgoingServerSockets.last,
            outgoing: incomingServerSockets.last,
            messagesSent: messagesSentController,
          ),
        ),
        messageCodec: codec,
      );

      final clientConnected = await client.connect();
      expect(clientConnected, isTrue);
      return client;
    }

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
      serverMessages = [];
      listenToMessages(serverMessagesSentController, serverMessages);

      final client1PeerId = PeerId.generate();
      client1MessagesSentController = StreamController<List<int>>.broadcast();
      client1Messages = [];
      listenToMessages(client1MessagesSentController, client1Messages);

      final client2PeerId = PeerId.generate();
      client2MessagesSentController = StreamController<List<int>>.broadcast();
      client2Messages = [];
      listenToMessages(client2MessagesSentController, client2Messages);

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
      server = WebSocketServer.test(
        serverFactory: () async => mockHttpServer,
        serverRegistry: registry,
        serverTransformer: mockWebSocketTransformer,
      );

      await registry.addDocument(documentId);
      final registryDoc = (await registry.getDocument(documentId))!;
      CRDTListHandler<String>(registryDoc, 'test-list');

      await server.start();

      client1 = await setupClient(
        peerId: client1PeerId,
        messagesSentController: client1MessagesSentController,
        codec: codec,
      );

      await Future<void>.delayed(Duration.zero);

      client2 = await setupClient(
        peerId: client2PeerId,
        messagesSentController: client2MessagesSentController,
        codec: codec,
      );

      await Future<void>.delayed(Duration.zero);

      // await handshake messages to be exchanged
      // Verify handshake messages were exchanged
      final handshakeClient1Requests = client1Messages
          .where((m) => m.type == MessageType.handshakeRequest)
          .toList();
      final handshakeClient2Requests = client2Messages
          .where((m) => m.type == MessageType.handshakeRequest)
          .toList();
      final handshakeServerResponses = serverMessages
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

    test('should handle communication between clients', () async {});
  });
}
