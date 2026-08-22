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
        incomingController = StreamController<List<int>>.broadcast(),
        _isDisconnected = false;

  /// Controller for outgoing messages
  /// (server writes here, client reads from here)
  final StreamController<List<int>> controller;

  /// Controller for incoming messages
  /// (client writes here, server reads from here)
  final StreamController<List<int>> incomingController;

  /// Flag to track if this socket has been disconnected
  bool _isDisconnected;

  /// Check if this socket is disconnected
  bool get isDisconnected => _isDisconnected;

  @override
  Stream<S> map<S>(S Function(dynamic event) convert) {
    // Server reads from incomingController, not from controller
    // This prevents the server from reading its own messages
    return incomingController.stream.map(convert);
  }

  /// Simulate a complete disconnection
  void simulateDisconnection() {
    simulateError();
    _isDisconnected = true;
  }

  /// Simulate a connection error
  void simulateError([Object? error]) {
    final err = error ?? Error();
    if (!controller.isClosed && !_isDisconnected) {
      controller.addError(err);
    }
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
    // Create two separate mock sockets for bidirectional communication
    final serverSocket = MockWebSocket();
    final clientSocket = MockWebSocket();

    serverSockets.add(serverSocket);
    clientSockets.add(clientSocket);

    // Mock server socket methods
    // In tests, we don't close the controllers to allow reconnection
    // The controllers should remain open so they can be reused
    when(() => serverSocket.close(any(), any())).thenAnswer((_) async {
      // Don't close the controllers - they are managed by the test
      // and should remain open for reuse during reconnection
    });
    when(() => clientSocket.close(any(), any())).thenAnswer((_) async {
      // Don't close the controllers - they are managed by the test
      // and should remain open for reuse during reconnection
    });

    when(() => serverSocket.add(any<List<int>>())).thenAnswer((invocation) {
      final data = invocation.positionalArguments[0] as List<int>;
      messagesSent.add(data);

      // Server writes to its own controller (client reads from this)
      // Only add if not disconnected and controller is not closed
      if (!serverSocket.isDisconnected) {
        serverSocket.controller.add(data);
      }
    });

    when(() => serverSocket.readyState).thenReturn(WebSocket.open);

    // bind client write to server incoming controller
    // Use a broadcast stream and handle errors gracefully
    // so the listener doesn't get closed when errors occur
    // This listener remains active even when errors occur,
    // allowing the connection to be reused during reconnection
    clientSocket.controller.stream.listen(
      serverSocket.incomingController.add,
      cancelOnError: false,
    );

    return serverSocket;
  });
}

/// [TransportConnector] for testing
///
/// When [connect] is called, a new [TransportConnection] is created
/// that uses:
///
/// - the [incoming] socket to receive messages
/// (read from its controller stream);
///
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
    // If the incoming socket is marked as disconnected,
    // throw an error to prevent reconnection
    if (incoming.isDisconnected) {
      throw Exception('Socket is permanently disconnected');
    }

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
  }) {
    // Create the stream once to avoid multiple subscriptions
    _incomingStream = incomingSocket.controller.stream;
  }

  final MockWebSocket incomingSocket;
  final MockWebSocket outgoingSocket;
  final StreamController<List<int>>? messagesSent;
  late final Stream<List<int>> _incomingStream;

  @override
  Stream<List<int>> get incoming => _incomingStream;

  @override
  Future<void> send(List<int> data) async {
    // Forward to messagesSent for inspection
    messagesSent?.add(data);
    outgoingSocket.controller.add(data);
  }

  @override
  Future<void> close() async {}

  @override
  bool get isConnected => true;
}
