import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpServer extends Mock implements HttpServer {}

class MockHttpRequest extends Mock implements HttpRequest {}

class MockHttpResponse extends Mock implements HttpResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}

class MockWebSocketTransformer extends Mock
    implements WebSocketServerTransformer {}

class MockWebSocket extends Mock implements Stream<dynamic>, WebSocket {
  MockWebSocket(this.webSocketController);

  final StreamController<dynamic> webSocketController;

  @override
  Stream<S> map<S>(S Function(dynamic event) convert) {
    return webSocketController.stream.map(convert);
  }
}

void main() {
  group('WebSocketServer', () {
    late MockHttpServer mockHttpServer;
    late StreamController<HttpRequest> httpRequestController;
    late StreamController<dynamic> webSocketController;
    late WebSocketServer server;
    late InMemoryCRDTServerRegistry registry;
    late MockWebSocketTransformer mockWebSocketTransformer;
    late MockWebSocket mockWebSocket;
    late JsonMessageCodec<Message> codec;
    late StreamController<List<int>> messageSent;

    setUp(() {
      messageSent = StreamController<List<int>>();
      mockHttpServer = MockHttpServer();
      httpRequestController = StreamController<HttpRequest>();
      registry = InMemoryCRDTServerRegistry();
      mockWebSocketTransformer = MockWebSocketTransformer();
      webSocketController = StreamController<List<int>>();
      mockWebSocket = MockWebSocket(webSocketController);
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
      webSocketController.close();
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
      when(() => mockWebSocketTransformer.upgrade(any()))
          .thenAnswer((_) async => mockWebSocket);

      // Mock web socket methods
      when(() => mockWebSocket.close(any(), any())).thenAnswer((_) async {});

      when(() => mockWebSocket.add(any<List<int>>())).thenAnswer((invocation) {
        final data = invocation.positionalArguments[0] as List<int>;
        messageSent.add(data);
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

      await server.start();
      server.serverEvents.listen((data) {
        if (data.type == ServerEventType.clientConnected) {
          completer.complete(data);
        }
      });
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

        await server.start();
        messageSent.stream.listen((data) {
          final message = codec.decode(data);
          completer.complete(message);
        });
        server.serverEvents.listen(events.add);

        httpRequestController.add(MockHttpRequest());

        final client = PeerId.generate();

        webSocketController.add(
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
  });
}
