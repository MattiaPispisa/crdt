import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/list/handler.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync/src/common/message.dart';
import 'package:crdt_socket_sync/src/common/transporter.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:test/test.dart';

import 'utils/stub.dart';

void main() {
  group('WebSocket Integration Tests', () {
    late MockHttpServer mockHttpServer;
    late StreamController<HttpRequest> httpRequestController;
    late MockWebSocketTransformer mockWebSocketTransformer;
    late WebSocketServer server;
    late InMemoryCRDTServerRegistry registry;
    late List<MockWebSocket> mockWebSockets;
    late JsonMessageCodec<Message> codec;
    late StreamController<List<int>> messagesSent;

    WebSocketClient? client1;
    WebSocketClient? client2;

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
      client1?.dispose();
      client2?.dispose();
      await server.stop();
      await registry.clear();
      httpRequestController.close();
      messagesSent.close();
      for (final mock in mockWebSockets) {
        await mock.controller.close();
      }
    });

    test('server and two clients should exchange messages', () async {
      final documentId = 'test-document-1';
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

      // Connect client 1 to server
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mockWebSockets.length, 1);

      final client1Doc = CRDTDocument(peerId: client1PeerId, documentId: documentId);
      final client1ListHandler = CRDTListHandler<String>(client1Doc, 'test-list');

      client1 = WebSocketClient.test(
        url: 'ws://localhost:8080',
        document: client1Doc,
        author: client1PeerId,
        transportFactory: () => Transport.create(
          MockTransportConnector(mockWebSockets[0]),
        ),
        messageCodec: codec,
      );
      final client1Connected = await client1!.connect();
      expect(client1Connected, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Connect client 2 to server
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mockWebSockets.length, 2);

      final client2Doc = CRDTDocument(peerId: client2PeerId, documentId: documentId);
      final client2ListHandler = CRDTListHandler<String>(client2Doc, 'test-list');

      client2 = WebSocketClient.test(
        url: 'ws://localhost:8080',
        document: client2Doc,
        author: client2PeerId,
        transportFactory: () => Transport.create(
          MockTransportConnector(mockWebSockets[1]),
        ),
        messageCodec: codec,
      );
      final client2Connected = await client2!.connect();
      expect(client2Connected, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Test: Client 1 sends a change and client 2 receives it
      expect(client1ListHandler.length, 0);
      client1ListHandler.insert(0, 'Item from C1');

      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Verify client 2 received the change
      expect(client2ListHandler.length, 1);
      expect(client2ListHandler[0], 'Item from C1');
    });
  });
}
