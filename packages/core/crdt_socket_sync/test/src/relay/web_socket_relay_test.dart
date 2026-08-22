@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:test/test.dart';
import '../utils/awareness.dart';
import '../utils/stub.dart';

/// A relay client bound to the in-memory socket harness, with the knob to
/// point it to a new socket pair for reconnection tests.
class _ClientSetup {
  _ClientSetup(this.client, this.updateSocketIndex);

  final WebSocketRelayClient client;
  final void Function(int) updateSocketIndex;
}

void main() {
  group('WebSocket relay integration', () {
    const port = 8080;
    const roomId = 'room-1';
    const handlerId = 'content';

    final codec = JsonMessageCodec<Message>(
      toJson: (message) => message.toJson(),
      fromJson: (json) => RelayMessage.fromJson(json) ?? Message.fromJson(json),
    );

    late StreamController<HttpRequest> httpRequestController;
    late MockHttpServer mockHttpServer;
    late MockWebSocketTransformer mockWebSocketTransformer;
    late List<MockWebSocket> outgoingServerSockets;
    late List<MockWebSocket> incomingServerSockets;
    late StreamController<List<int>> serverMessagesSentController;
    late InMemoryRelayStore store;
    late WebSocketRelayServer server;
    late List<WebSocketRelayClient> clients;

    setUp(() {
      httpRequestController = StreamController<HttpRequest>.broadcast();
      mockHttpServer = MockHttpServer();
      mockWebSocketTransformer = MockWebSocketTransformer();
      outgoingServerSockets = [];
      incomingServerSockets = [];
      serverMessagesSentController = StreamController<List<int>>.broadcast();
      store = InMemoryRelayStore();
      clients = [];

      stubHttpServer(
        mockHttpServer: mockHttpServer,
        httpRequestController: httpRequestController,
      );
      stubWebSocket(
        mockWebSocketTransformer: mockWebSocketTransformer,
        serverSockets: outgoingServerSockets,
        clientSockets: incomingServerSockets,
        messagesSent: serverMessagesSentController,
      );
    });

    tearDown(() async {
      for (final client in clients) {
        client.dispose();
      }
      await server.dispose();
      await httpRequestController.close();
      await serverMessagesSentController.close();
    });

    Future<void> startServer({
      RelayCompactionCoordinator? compaction,
      List<ServerSyncPlugin>? plugins,
    }) async {
      server = WebSocketRelayServer.test(
        serverFactory: () async => mockHttpServer,
        serverTransformer: mockWebSocketTransformer,
        store: store,
        compaction: compaction,
        messageCodec: codec,
        plugins: plugins,
      );
      expect(await server.start(), isTrue);
    }

    /// Add a client connection to the server
    /// (send an "upgrade request" to the server)
    Future<void> addClientConnection() async {
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
    }

    /// Setup a relay client connected to the server through a fresh
    /// in-memory socket pair.
    Future<_ClientSetup> setupClient({
      required String documentId,
      List<ClientSyncPlugin>? plugins,
    }) async {
      await addClientConnection();
      var currentSocketIndex = outgoingServerSockets.length - 1;

      final document = CRDTDocument(
        peerId: PeerId.generate(),
        documentId: documentId,
      );

      final client = WebSocketRelayClient.test(
        url: 'ws://localhost:$port',
        document: document,
        author: document.peerId,
        messageCodec: codec,
        // Fast, deterministic reconnects for the tests.
        reconnectBaseDelay: const Duration(milliseconds: 10),
        reconnectMaxDelay: const Duration(milliseconds: 40),
        reconnectJitter: Duration.zero,
        transportFactory: () => Transport.create(
          MockTransportConnector(
            incoming: outgoingServerSockets[currentSocketIndex],
            outgoing: incomingServerSockets[currentSocketIndex],
          ),
        ),
        plugins: plugins,
      );
      clients.add(client);

      expect(await client.connect(), isTrue);

      return _ClientSetup(
        client,
        (int newIndex) => currentSocketIndex = newIndex,
      );
    }

    /// Polls [condition] until it holds or [timeout] expires.
    Future<void> waitUntil(
      FutureOr<bool> Function() condition, {
      Duration timeout = const Duration(seconds: 2),
      String? reason,
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!await condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail(reason ?? 'condition not met within $timeout');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('two clients converge through the relay', () async {
      await startServer();

      final setup1 = await setupClient(documentId: roomId);
      final setup2 = await setupClient(documentId: roomId);
      final handler1 = CRDTFugueTextHandler(setup1.client.document, handlerId);
      final handler2 = CRDTFugueTextHandler(setup2.client.document, handlerId);

      handler1.insert(0, 'hello');
      handler2.insert(0, 'world');

      await waitUntil(
        () =>
            handler1.value == handler2.value &&
            handler1.value.contains('hello') &&
            handler1.value.contains('world'),
        reason: 'concurrent inserts must converge on both clients',
      );

      // The relay persisted the blobs without interpreting them.
      expect(await store.logLength(roomId), greaterThan(0));
      expect(setup1.client.pendingChangesCount, 0);
      expect(setup2.client.pendingChangesCount, 0);
    });

    test('a late joiner catches up from the welcome', () async {
      await startServer();

      final setup1 = await setupClient(documentId: roomId);
      CRDTFugueTextHandler(setup1.client.document, handlerId)
          .insert(0, 'hello');
      await waitUntil(
        () =>
            setup1.client.pendingChangesCount == 0 &&
            setup1.client.lastKnownSeq > 0,
        reason: 'the edit must be acked before the late joiner connects',
      );

      final setup2 = await setupClient(documentId: roomId);
      final handler2 = CRDTFugueTextHandler(setup2.client.document, handlerId);

      await waitUntil(
        () => handler2.value == 'hello',
        reason: 'the late joiner must rebuild the state from the welcome',
      );
      expect(setup2.client.lastKnownSeq, setup1.client.lastKnownSeq);
    });

    test('unacked changes survive a reconnect and reach the other client',
        () async {
      await startServer();

      final setup1 = await setupClient(documentId: roomId);
      final setup2 = await setupClient(documentId: roomId);
      final handler1 = CRDTFugueTextHandler(setup1.client.document, handlerId);
      final handler2 = CRDTFugueTextHandler(setup2.client.document, handlerId);

      final oldSocketIndex = outgoingServerSockets.length - 2;

      // Kill the current connection: reconnect attempts fail until a new
      // socket pair is provided below.
      final dropped = setup1.client.connectionStatus
          .firstWhere((status) => !status.isConnected);
      outgoingServerSockets[oldSocketIndex].simulateDisconnection();
      await dropped;

      // Edit while offline: the change is queued, not lost.
      handler1.insert(0, 'offline');
      await Future<void>.delayed(Duration.zero);
      expect(setup1.client.pendingChangesCount, greaterThan(0));

      // Bring the connection back through a fresh socket pair.
      await addClientConnection();
      setup1.updateSocketIndex(outgoingServerSockets.length - 1);

      await waitUntil(
        () => handler2.value == 'offline',
        reason: 'the queued change must be delivered after the reconnect',
      );
      expect(setup1.client.pendingChangesCount, 0);
    });

    test('compaction truncates the log and late joiners still converge',
        () async {
      await startServer(
        compaction: RelayCompactionCoordinator(logCompactThreshold: 3),
      );

      final setup1 = await setupClient(documentId: roomId);
      final handler1 = CRDTFugueTextHandler(setup1.client.document, handlerId);

      // One change per insert: enough pushes to cross the threshold.
      for (var i = 0; i < 6; i++) {
        handler1.insert(i, 'a');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await waitUntil(
        () async => await store.getSnapshot(roomId) != null,
        reason: 'crossing the log threshold must trigger a snapshot upload',
      );

      final snapshot = (await store.getSnapshot(roomId))!;
      expect(snapshot.upToSeq, greaterThan(3));
      expect(
        await store.logLength(roomId),
        lessThan(await store.lastSeq(roomId)),
        reason: 'the covered log entries must be deleted',
      );

      final setup2 = await setupClient(documentId: roomId);
      final handler2 = CRDTFugueTextHandler(setup2.client.document, handlerId);
      await waitUntil(
        () => handler2.value == 'aaaaaa',
        reason: 'a late joiner must rebuild from snapshot plus residual log',
      );
      expect(handler1.value, 'aaaaaa');
    });

    test('awareness flows through the relay', () async {
      final serverAwareness = ServerAwarenessPlugin();
      await startServer(plugins: [serverAwareness]);

      final client1Awareness = ClientAwarenessPlugin(
        throttleDuration: const Duration(milliseconds: 10),
      );
      final client2Awareness = ClientAwarenessPlugin(
        throttleDuration: const Duration(milliseconds: 10),
      );

      final setup1 = await setupClient(
        documentId: roomId,
        plugins: [client1Awareness],
      );
      await setupClient(
        documentId: roomId,
        plugins: [client2Awareness],
      );

      final client1Id = setup1.client.sessionId!;
      client1Awareness.updateLocalState({'cursor': 3});

      await waitUntil(
        () => client2Awareness.awareness.states[client1Id] != null,
        reason: "client2 must receive client1's awareness state",
      );
      expect(
        client2Awareness.awareness.states[client1Id],
        ClientAwarenessMatcher(
          clientAwareness: ClientAwareness(
            clientId: client1Id,
            metadata: {'cursor': 3},
          ),
        ),
      );

      // Presence is ephemeral: nothing about awareness is persisted.
      expect(await store.logLength(roomId), 0);
    });

    test('rooms are isolated on a multi-room server', () async {
      await startServer();

      final setupA1 = await setupClient(documentId: 'room-a');
      final setupA2 = await setupClient(documentId: 'room-a');
      final setupB1 = await setupClient(documentId: 'room-b');
      final handlerA1 =
          CRDTFugueTextHandler(setupA1.client.document, handlerId);
      final handlerA2 =
          CRDTFugueTextHandler(setupA2.client.document, handlerId);
      final handlerB1 =
          CRDTFugueTextHandler(setupB1.client.document, handlerId);

      handlerA1.insert(0, 'alpha');
      handlerB1.insert(0, 'beta');

      await waitUntil(
        () => handlerA2.value == 'alpha' && handlerB1.value == 'beta',
        reason: 'each room must converge independently',
      );
      expect(handlerB1.value, 'beta');
      expect(handlerA2.value, 'alpha');

      expect(await store.roomIds, {'room-a', 'room-b'});
      expect(await store.logLength('room-b'), greaterThan(0));
    });
  });
}
