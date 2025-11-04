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
  MockWebSocket()
      : controller = StreamController<List<int>>.broadcast(),
        incomingController = StreamController<List<int>>.broadcast();

  /// Controller for outgoing messages (server writes here, client reads from here)
  final StreamController<List<int>> controller;

  /// Controller for incoming messages (client writes here, server reads from here)
  final StreamController<List<int>> incomingController;

  @override
  Stream<S> map<S>(S Function(dynamic event) convert) {
    // Server reads from incomingController, not from controller
    // This prevents the server from reading its own messages
    return incomingController.stream.map(convert);
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
/// Creates two paired [MockWebSocket] instances:
/// - serverSocket: used by the server (writes to client, reads from client)
/// - clientSocket: used by the client (writes to server, reads from server)
///
/// The [messagesSent] controller is used to capture all sent messages
/// from both server and client for inspection.
void stubWebSocket({
  required MockWebSocketTransformer mockWebSocketTransformer,
  required List<MockWebSocket> serverSockets,
  required List<MockWebSocket> clientSockets,
  required StreamController<List<int>> messagesSent,
}) {
  // Mock the request upgrade to websocket
  when(() => mockWebSocketTransformer.isUpgradeRequest(any())).thenReturn(true);
  when(() => mockWebSocketTransformer.upgrade(any())).thenAnswer((_) async {
    print("UPGRADE");
    // Create two separate mock sockets for bidirectional communication
    final serverSocket = MockWebSocket();
    final clientSocket = MockWebSocket();

    serverSockets.add(serverSocket);
    clientSockets.add(clientSocket);

    // Mock server socket methods
    when(() => serverSocket.close(any(), any())).thenAnswer((_) async {
    });

    when(() => serverSocket.add(any<List<int>>())).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0] as List<int>;
      messagesSent.add(data);
      // Server writes to its own controller (client reads from this)
      serverSocket.controller.add(data);
    });

    when(() => serverSocket.readyState).thenReturn(WebSocket.open);

    // bind client write to server incoming controller
    clientSocket.controller.stream.listen(serverSocket.incomingController.add);

    return serverSocket;
  });
}

/// [TransportConnector] for testing
///
/// When [connect] is called, a new [TransportConnection] is created
/// that uses:
/// - the [incoming] socket to receive messages (read from its controller stream);
/// - the [outgoing] socket to send messages (write to its controller).
///
/// If [messagesSent] is provided,
/// all sent messages will also be added to it for inspection.
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
  Future<void> close() async {}

  @override
  bool get isConnected => true;
}
