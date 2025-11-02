import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:test/test.dart';

import 'utils/stub.dart';

void main() {
  group('WebSocket Integration Tests', () {
    late MockHttpServer mockHttpServer;
    late StreamController<HttpRequest> httpRequestController;
    late MockWebSocketTransformer mockWebSocketTransformer;
    late InMemoryCRDTServerRegistry registry;
    late List<MockWebSocket> mockWebSockets;
    late JsonMessageCodec<Message> codec;
    late StreamController<List<int>> messagesSent;

    setUp(() {
      messagesSent = StreamController<List<int>>.broadcast();
      mockHttpServer = MockHttpServer();
      httpRequestController = StreamController<HttpRequest>.broadcast();
      registry = InMemoryCRDTServerRegistry();
      mockWebSocketTransformer = MockWebSocketTransformer();
      mockWebSockets = [];
      codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: Message.fromJson,
      );
    });

    tearDown(() async {
      await registry.clear();
      await httpRequestController.close();
      await messagesSent.close();
      for (final mock in mockWebSockets) {
        await mock.controller.close();
      }
    });

    /// Setup a client and connect it to the server
    /// (send an "upgrade request" to the server)
    ///
    /// Returns the client instance
    Future<WebSocketClient> setupClient({
      required PeerId peerId,
      required String documentId,
    }) async {
      final webSocketCount = mockWebSockets.length;

      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        mockWebSockets.length,
        webSocketCount + 1,
        reason: 'After upgrade request, the number of web sockets '
            'should be incremented by 1',
      );

      final clientDoc = CRDTDocument(peerId: peerId, documentId: documentId);

      final client = WebSocketClient.test(
        url: 'ws://localhost:8080',
        document: clientDoc,
        author: peerId,
        transportFactory: () => Transport.create(
          MockTransportConnector(mockWebSockets.last),
        ),
        messageCodec: codec,
      );

      final clientConnected = await client.connect();
      expect(clientConnected, isTrue);

      return client;
    }

    test(
        'should setup a communication between '
        'two clients and a server', () async {
      const documentId = 'test-document-1';
      final client1PeerId = PeerId.generate();
      final client2PeerId = PeerId.generate();

      // Setup stubs
      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        mockWebSockets: mockWebSockets,
        messagesSent: messagesSent,
      );

      // Create server with WebSocketServer.test
      final server = WebSocketServer.test(
        serverFactory: () async => mockHttpServer,
        serverRegistry: registry,
        serverTransformer: mockWebSocketTransformer,
      );

      await registry.addDocument(documentId);
      final registryDoc = (await registry.getDocument(documentId))!;
      CRDTListHandler<String>(registryDoc, 'test-list');

      await server.start();

      final client1 = await setupClient(
        peerId: client1PeerId,
        documentId: documentId,
      );

      await Future<void>.delayed(Duration.zero);

      final client2 = await setupClient(
        peerId: client2PeerId,
        documentId: documentId,
      );

      await Future<void>.delayed(Duration.zero);

      final client1ListHandler =
          CRDTListHandler<String>(client1.document, 'test-list');

      final client2ListHandler =
          CRDTListHandler<String>(client2.document, 'test-list');

      // Test: Client 1 sends a change and client 2 receives it
      expect(client1ListHandler.length, 0);
      client1ListHandler.insert(0, 'Item from C1');

      await Future<void>.delayed(Duration.zero);

      // Verify client 2 received the change
      expect(client2ListHandler.length, 1);
      expect(client2ListHandler[0], 'Item from C1');

      final serverMessages = <Message>[];
      final client1Messages = <Message>[];

      messagesSent.stream.listen((data) {
        final message = codec.decode(data);
        if (message != null) {
          serverMessages.add(message);
        }
      });

      

    });

    group('should handle communication between clients', () {
      const documentId = 'd77712cf-ec51-4448-bc2e-bd8e6d72d741';
      late WebSocketServer server;
      late WebSocketClient client1;
      late WebSocketClient client2;

      setUp(() async {
        final client1PeerId = PeerId.generate();
        final client2PeerId = PeerId.generate();

        // Setup stubs
        stubHttpServer(
          mockHttpServer: mockHttpServer,
          httpRequestController: httpRequestController,
        );
        stubWebSocket(
          mockWebSocketTransformer: mockWebSocketTransformer,
          mockWebSockets: mockWebSockets,
          messagesSent: messagesSent,
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
          documentId: documentId,
        );

        await Future<void>.delayed(Duration.zero);

        client2 = await setupClient(
          peerId: client2PeerId,
          documentId: documentId,
        );

        await Future<void>.delayed(Duration.zero);
      });

      tearDown(() async {
        client1.dispose();
        client2.dispose();
        await server.stop();
      });
    });
  });
}
