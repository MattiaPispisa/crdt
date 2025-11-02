import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:mocktail/mocktail.dart';

/// Mock implementations for WebSocket server testing
class MockHttpServer extends Mock implements HttpServer {}

class MockHttpRequest extends Mock implements HttpRequest {}

class MockHttpResponse extends Mock implements HttpResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}

class MockWebSocketTransformer extends Mock
    implements WebSocketServerTransformer {}

class MockWebSocket extends Mock implements Stream<dynamic>, WebSocket {
  MockWebSocket() : controller = StreamController<List<int>>.broadcast();

  final StreamController<List<int>> controller;

  @override
  Stream<S> map<S>(S Function(dynamic event) convert) {
    return controller.stream.map(convert);
  }
}

/// Stub configuration for HTTP server in tests
///
/// When [mockHttpServer] is listened
/// the [httpRequestController] is returned.
void stubHttpServer({
  required MockHttpServer mockHttpServer,
  required StreamController<HttpRequest> httpRequestController,
  int port = 8080,
}) {
  registerFallbackValue(MockHttpRequest());

  // Mock the http server
  when(() => mockHttpServer.address).thenReturn(InternetAddress.loopbackIPv4);
  when(() => mockHttpServer.port).thenReturn(port);
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
      onError: invocation.namedArguments[const Symbol('onError')] as Function?,
      cancelOnError:
          invocation.namedArguments[const Symbol('cancelOnError')] as bool?,
      onDone:
          invocation.namedArguments[const Symbol('onDone')] as void Function()?,
    );
  });
  when(() => mockHttpServer.close()).thenAnswer((_) async {});
}

/// Stub configuration for WebSocket upgrades in tests
///
/// When [mockWebSocketTransformer] is called to upgrade a request
/// to a web socket, a new [MockWebSocket] is created
/// and added to both the [serverSockets] and [clientSockets] lists.
/// This allows bidirectional communication through the same mock socket.
///
/// The [messagesSent] controller is used to send messages from both server
/// and client for inspection.
void stubWebSocket({
  required MockWebSocketTransformer mockWebSocketTransformer,
  required List<MockWebSocket> serverSockets,
  required List<MockWebSocket> clientSockets,
  required StreamController<List<int>> messagesSent,
}) {
  // Mock the request upgrade to websocket
  when(() => mockWebSocketTransformer.isUpgradeRequest(any())).thenReturn(true);
  when(() => mockWebSocketTransformer.upgrade(any())).thenAnswer((_) async {
    final mockWebSocket = MockWebSocket();
    serverSockets.add(mockWebSocket);
    clientSockets.add(mockWebSocket);

    // Mock web socket methods
    when(() => mockWebSocket.close(any(), any())).thenAnswer((_) async {});

    when(() => mockWebSocket.add(any<List<int>>())).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0] as List<int>;
      messagesSent.add(data);
      // Server's _WebSocketConnection.send() calls _webSocket.add(),
      // forward to controller
      mockWebSocket.controller.add(data);
    });

    when(() => mockWebSocket.readyState).thenReturn(WebSocket.open);

    return mockWebSocket;
  });
}

/// [TransportConnector] for testing
///
/// When [connect] is called, a new [TransportConnection] is created
/// that uses:
/// - the [incoming] to send messages;
/// - the [outgoing] to receive messages.
///
/// If [messagesSent] is provided,
/// all sent messages will also be added to it.
class MockTransportConnector implements TransportConnector {
  MockTransportConnector({
    required this.incoming,
    required this.outgoing,
    this.messagesSent,
  });

  final MockWebSocket incoming;
  final MockWebSocket outgoing;
  final StreamController<List<int>>? messagesSent;

  @override
  Future<TransportConnection> connect() async {
    return _MockTransportConnection(
      incomingSocket: incoming,
      outgoingSocket: outgoing,
      messagesSent: messagesSent,
    );
  }
}

/// TransportConnection implementation for testing using MockWebSocket
class _MockTransportConnection implements TransportConnection {
  _MockTransportConnection({
    required this.incomingSocket,
    required this.outgoingSocket,
    this.messagesSent,
  });

  final MockWebSocket incomingSocket;
  final MockWebSocket outgoingSocket;
  final StreamController<List<int>>? messagesSent;

  @override
  Stream<List<int>> get incoming => incomingSocket.controller.stream;

  @override
  Future<void> send(List<int> data) async {
    // Forward to messagesSent for inspection
    messagesSent?.add(data);
    // Forward to controller for receiver to consume
    outgoingSocket.controller.add(data);
  }

  @override
  Future<void> close() async {
    await outgoingSocket.controller.close();
  }

  @override
  bool get isConnected => true;
}
