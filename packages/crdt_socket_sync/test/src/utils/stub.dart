import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/transporter.dart';
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
void stubHttpServer({
  required MockHttpServer mockHttpServer,
  required StreamController<HttpRequest> httpRequestController,
}) {
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
      onError: invocation.namedArguments[const Symbol('onError')] as Function?,
      cancelOnError:
          invocation.namedArguments[const Symbol('cancelOnError')] as bool?,
      onDone: invocation.namedArguments[const Symbol('onDone')] as void
          Function()?,
    );
  });
  when(() => mockHttpServer.close()).thenAnswer((_) async {});
}

/// Stub configuration for WebSocket upgrades in tests
void stubWebSocket({
  required MockWebSocketTransformer mockWebSocketTransformer,
  required List<MockWebSocket> mockWebSockets,
  required StreamController<List<int>> messagesSent,
}) {
  // Mock the request upgrade to websocket
  when(() => mockWebSocketTransformer.isUpgradeRequest(any()))
      .thenReturn(true);
  when(() => mockWebSocketTransformer.upgrade(any())).thenAnswer((_) async {
    final mockWebSocket = MockWebSocket();
    mockWebSockets.add(mockWebSocket);

    // Mock web socket methods
    when(() => mockWebSocket.close(any(), any())).thenAnswer((_) async {});

    when(() => mockWebSocket.add(any<List<int>>())).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0] as List<int>;
      messagesSent.add(data);
      // Server's _WebSocketConnection.send() calls _webSocket.add(), forward to controller
      mockWebSocket.controller.add(data);
    });
    
    when(() => mockWebSocket.readyState).thenReturn(WebSocket.open);

    return mockWebSocket;
  });
}

/// TransportConnection implementation for testing using MockWebSocket
class MockTransportConnection implements TransportConnection {
  MockTransportConnection({
    required this.mockWebSocket,
  });

  final MockWebSocket mockWebSocket;

  @override
  Stream<List<int>> get incoming => mockWebSocket.controller.stream;

  @override
  Future<void> send(List<int> data) async {
    mockWebSocket.controller.add(data);
  }

  @override
  Future<void> close() async {
    await mockWebSocket.controller.close();
  }

  @override
  bool get isConnected => true;
}

/// TransportConnector for testing that returns a MockTransportConnection
class MockTransportConnector implements TransportConnector {
  MockTransportConnector(this.mockWebSocket);

  final MockWebSocket mockWebSocket;

  @override
  Future<TransportConnection> connect() async {
    return MockTransportConnection(mockWebSocket: mockWebSocket);
  }
}

/// TransportConnection implementation using StreamControllers for testing
class StreamTransportConnection implements TransportConnection {
  StreamTransportConnection({
    required this.incomingController,
    required this.outgoingController,
  });

  final StreamController<List<int>> incomingController;
  final StreamController<List<int>> outgoingController;

  @override
  Stream<List<int>> get incoming => incomingController.stream;

  @override
  Future<void> send(List<int> data) async {
    outgoingController.add(data);
  }

  @override
  Future<void> close() async {
    await incomingController.close();
    await outgoingController.close();
  }

  @override
  bool get isConnected => !incomingController.isClosed;
}

/// TransportConnector that returns a StreamTransportConnection
class StreamTransportConnector implements TransportConnector {
  StreamTransportConnector({
    required this.incomingController,
    required this.outgoingController,
  });

  final StreamController<List<int>> incomingController;
  final StreamController<List<int>> outgoingController;

  @override
  Future<TransportConnection> connect() async {
    return StreamTransportConnection(
      incomingController: incomingController,
      outgoingController: outgoingController,
    );
  }
}

/// Internal class used to setup the server for testing
///
/// This contains the messages sent from the server to the clients
/// and the events emitted by the server
class ServerSetup {
  ServerSetup({
    required this.serverMessages,
    required this.serverEvents,
  });

  /// Messages sent from the server to the clients
  final List<Message> serverMessages;

  /// Events emitted by the server
  final List<ServerEvent> serverEvents;
}

