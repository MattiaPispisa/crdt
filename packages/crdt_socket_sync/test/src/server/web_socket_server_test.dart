import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../utils/mock_operation.dart';

class MockHttpServer extends Mock implements HttpServer {}

class MockHttpRequest extends Mock implements HttpRequest {}

class MockHttpResponse extends Mock implements HttpResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}

class MockWebSocketTransformer extends Mock
    implements WebSocketServerTransformer {}

class MockWebSocket extends Mock implements Stream<dynamic>, WebSocket {
  MockWebSocket() : controller = StreamController<List<int>>();

  final StreamController<List<int>> controller;

  @override
  Stream<S> map<S>(S Function(dynamic event) convert) {
    return controller.stream.map(convert);
  }
}

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
    /// sent from the server to the client
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

    void stubHttpServer() {
      registerFallbackValue(MockHttpRequest());

      // Mock the http server
      when(() => mockHttpServer.address)
          .thenReturn(InternetAddress.loopbackIPv4);
      when(() => mockHttpServer.port).thenReturn(8080);
      when(
        () => mockHttpServer.listen(
          any(),
          onError: any(named: 'onError'),
          cancelOnError: any(named: 'cancelOnError'),
          onDone: any(named: 'onDone'),
        ),
      ).thenAnswer((invocation) {
        final onData =
            invocation.positionalArguments[0] as void Function(HttpRequest);
        return httpRequestController.stream.listen(
          onData,
          onError:
              invocation.namedArguments[const Symbol('onError')] as Function?,
          cancelOnError:
              invocation.namedArguments[const Symbol('cancelOnError')] as bool?,
          onDone: invocation.namedArguments[const Symbol('onDone')] as void
              Function()?,
        );
      });
      when(() => mockHttpServer.close()).thenAnswer((_) async {});
    }

    void stubWebSocket() {
      // Mock the request upgrade to websocket
      when(() => mockWebSocketTransformer.isUpgradeRequest(any()))
          .thenReturn(true);
      when(() => mockWebSocketTransformer.upgrade(any())).thenAnswer((_) async {
        final mockWebSocket = MockWebSocket();
        mockWebSockets.add(mockWebSocket);

        // Mock web socket methods
        when(() => mockWebSocket.close(any(), any())).thenAnswer((_) async {});

        when(() => mockWebSocket.add(any<List<int>>()))
            .thenAnswer((invocation) {
          final data = invocation.positionalArguments[0] as List<int>;
          messagesSent.add(data);
        });

        return mockWebSocket;
      });
    }

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

    test('should start the server', () async {
      stubHttpServer();

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
      stubHttpServer();
      stubWebSocket();

      final started = await server.start();
      expect(started, isTrue);

      httpRequestController.add(MockHttpRequest());

      await Future<void>.delayed(Duration.zero);

      verify(() => mockWebSocketTransformer.upgrade(any())).called(1);
    });

    test('should create a session', () async {
      final completer = Completer<ServerEvent>();

      stubHttpServer();
      stubWebSocket();

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

        stubHttpServer();
        stubWebSocket();

        registry.addDocument(documentId, CRDTDocument());

        messagesSent.stream.listen((data) {
          final message = codec.decode(data);
          completer.complete(message);
        });
        server.serverEvents.listen(events.add);
        await server.start();

        httpRequestController.add(MockHttpRequest());
        final client = PeerId.generate();
        await Future<void>.delayed(Duration.zero);

        mockWebSockets.first.controller.add(
          codec.encode(
            HandshakeRequestMessage(
              author: client,
              documentId: documentId,
              version: {},
            ),
          ),
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
          contains('Client handshake completed:'),
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

      stubHttpServer();
      stubWebSocket();

      registry.addDocument(documentId, CRDTDocument());

      messagesSent.stream.listen((data) {
        final message = codec.decode(data);
        serverMessages.add(message);

        if (serverMessages.length == 2) {
          completer.complete(true);
        }
      });
      server.serverEvents.listen(serverEvents.add);
      await server.start();

      // Client 1
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSockets[0].controller.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client1,
                documentId: documentId,
                version: {},
              ),
            ),
          );

      // Client 2
      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSockets[1].controller.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client2,
                documentId: documentId,
                version: {},
              ),
            ),
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

    Future<ServerSetup> setupServer({
      void Function(Message)? onMessage,
      void Function(ServerEvent)? onEvent,
    }) async {
      stubHttpServer();
      stubWebSocket();

      final serverMessages = <Message>[];
      final serverEvents = <ServerEvent>[];

      messagesSent.stream.listen((data) {
        final message = codec.decode(data);
        serverMessages.add(message);
        onMessage?.call(message);
      });
      server.serverEvents.listen((event) {
        serverEvents.add(event);
        onEvent?.call(event);
      });

      await server.start();

      return ServerSetup(
        serverMessages: serverMessages,
        serverEvents: serverEvents,
      );
    }

    Future<void> addClient({
      required String documentId,
      PeerId? clientId,
    }) async {
      final client = clientId ?? PeerId.generate();

      httpRequestController.add(MockHttpRequest());
      await Future<void>.delayed(Duration.zero);
      mockWebSockets[0].controller.add(
            codec.encode(
              HandshakeRequestMessage(
                author: client,
                documentId: documentId,
                version: {},
              ),
            ),
          );
    }

    test('should handle incoming changes', () async {
      final documentId = PeerId.generate();
      final client1 = PeerId.generate();
      final client2 = PeerId.generate();

// server doc
      final serverDoc = CRDTDocument(peerId: documentId);
      CRDTListHandler<String>(serverDoc, 'list');
      registry.addDocument(documentId.id, serverDoc);

// client doc
      final clientDoc = CRDTDocument(peerId: documentId);
      CRDTListHandler<String>(clientDoc, 'list').insert(0, 'Hello');
      final change = clientDoc.exportChanges().first;

      final setup = await setupServer();

      await addClient(documentId: documentId.id, clientId: client1);
      await addClient(documentId: documentId.id, clientId: client2);

      await Future<void>.delayed(Duration.zero);

      mockWebSockets[0].controller.add(
            codec.encode(
              ChangeMessage(
                change: change,
                documentId: documentId.id,
              ),
            ),
          );

      await Future<void>.delayed(Duration.zero);
      expect(setup.serverMessages.length, 2);
      expect(setup.serverEvents.length, 6);
      expect(setup.serverEvents[5].type, ServerEventType.clientChangeApplied);

      // TODO: test broadcast to other clients
    });
  });
}

class ServerSetup {
  ServerSetup({
    required this.serverMessages,
    required this.serverEvents,
  });

  final List<Message> serverMessages;
  final List<ServerEvent> serverEvents;
}
