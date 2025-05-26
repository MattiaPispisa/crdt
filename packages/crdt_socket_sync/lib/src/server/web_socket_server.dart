import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/server/client_session.dart';
import 'package:crdt_socket_sync/src/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server/event.dart';
import 'package:crdt_socket_sync/src/server/registry.dart';
import 'package:crdt_socket_sync/src/server/server.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket server implementation
class WebSocketServer implements CRDTSocketServer {
  /// Constructor
  WebSocketServer({
    required this.host,
    required this.port,
    required CRDTServerRegistry documentRegistry,
    Compressor? compressor,
  })  : _compressor = compressor ?? NoCompression.instance,
        _serverEventController = StreamController<ServerEvent>.broadcast(),
        _serverRegistry = documentRegistry;

  /// The document registry
  final CRDTServerRegistry _serverRegistry;

  /// The server host
  final String host;

  /// The server port
  final int port;

  /// The server
  HttpServer? _server;

  /// Active client sessions
  final Map<String, ClientSession> _sessions = {};

  /// Controller for the server event stream
  final StreamController<ServerEvent> _serverEventController;

  /// Server event stream
  @override
  Stream<ServerEvent> get serverEvents => _serverEventController.stream;

  /// If the server is running
  bool _isRunning = false;

  /// Compressor to use
  final Compressor _compressor;

  /// Start the server
  ///
  /// Returns true if the server is started, false otherwise
  ///
  /// 1. Check if the server is already running
  /// 1. Start the server
  /// 1. Upgrade the request to a WebSocket connection
  @override
  Future<bool> start() async {
    if (_isRunning) {
      return true;
    }

    try {
      _server = await HttpServer.bind(host, port);

      _serverEventController.add(
        ServerEvent(
          type: ServerEventType.started,
          message: 'Server started on $host:$port',
        ),
      );

      _isRunning = true;

      _server!.listen((request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then(_handleWebSocket);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.close();
        }
      });

      return true;
    } catch (e) {
      _serverEventController.add(
        ServerEvent(
          type: ServerEventType.error,
          message: 'Failed to start server: $e',
        ),
      );
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;

    // close sessions
    for (final session in _sessions.values) {
      await session.close();
    }
    _sessions.clear();

    await _server?.close();
    _server = null;

    _serverEventController.add(
      const ServerEvent(
        type: ServerEventType.stopped,
        message: 'Server stopped',
      ),
    );
  }

  @override
  Snapshot createSnapshot(String documentId) {
    final snapshot = _serverRegistry.createSnapshot(documentId);

    _serverEventController.add(
      ServerEvent(
        type: ServerEventType.snapshotCreated,
        message: 'Snapshot created for document: $documentId',
        data: {
          'documentId': documentId,
        },
      ),
    );

    return snapshot;
  }

  @override
  Future<void> sendMessageToClient(String clientId, Message message) async {
    final session = _sessions[clientId];
    if (session != null) {
      await session.sendMessage(message);
    }
  }

  @override
  Future<void> broadcastMessage(
    Message message, {
    List<String>? excludeClientIds,
  }) async {
    final documentId = message.documentId;

    for (final session in _sessions.values) {
      final isExcluded = excludeClientIds?.contains(session.id) ?? false;
      final isSubscribed = session.isSubscribedTo(documentId);

      if (!isExcluded && isSubscribed) {
        await session.sendMessage(message);
      }
    }
  }

  /// Handle a new WebSocket connection
  ///
  /// 1. setup the [TransportConnection]
  /// 1. create a new [ClientSession]
  void _handleWebSocket(WebSocket webSocket) {
    // Generate a unique session ID
    final sessionId = _generateSessionId();

    final connection = _WebSocketConnection(webSocket);

    final session = ClientSession(
      id: sessionId,
      connection: connection,
      serverRegistry: _serverRegistry,
      compressor: _compressor,
    );

    _sessions[sessionId] = session;

    _serverEventController.add(
      ServerEvent(
        type: ServerEventType.clientConnected,
        message: 'Client connected: $sessionId',
        data: {
          'clientId': sessionId,
        },
      ),
    );

    session.events.listen(
      _handleSessionEvent,
      onDone: () => _handleSessionClosed(sessionId),
      onError: (dynamic error) => _handleSessionError(sessionId, error),
    );
  }

  void _handleSessionEventHandshakeCompleted(SessionEventGeneric event) {
    _serverEventController.add(
      ServerEvent(
        type: ServerEventType.clientHandshake,
        message: 'Client handshake completed: ${event.message}',
        data: event.data,
      ),
    );
  }

  Future<void> _handleSessionEventChangeReceived(
    SessionEventChangeReceived event,
  ) {
    return broadcastMessage(
      Message.change(event.documentId, event.change),
      excludeClientIds: [event.sessionId],
    );
  }

  void _handleSessionEventError(SessionEventGeneric event) {
    _serverEventController.add(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session error: ${event.message}',
        data: event.data,
      ),
    );
  }

  /// Handle a session event
  FutureOr<void> _handleSessionEvent(SessionEvent event) async {
    switch (event.type) {
      case SessionEventType.handshakeCompleted:
        return _handleSessionEventHandshakeCompleted(
          event as SessionEventGeneric,
        );

      case SessionEventType.changeReceived:
        return _handleSessionEventChangeReceived(
          event as SessionEventChangeReceived,
        );

      case SessionEventType.error:
        return _handleSessionEventError(
          event as SessionEventGeneric,
        );

      case SessionEventType.disconnected:
        return;
    }
  }

  /// Handle session closed
  void _handleSessionClosed(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      session.dispose();

      _serverEventController.add(
        ServerEvent(
          type: ServerEventType.clientDisconnected,
          message: 'Client disconnected: $sessionId',
          data: {
            'clientId': sessionId,
          },
        ),
      );
    }
  }

  /// Handle session error
  void _handleSessionError(String sessionId, dynamic error) {
    _serverEventController.add(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session error: $error',
        data: {
          'clientId': sessionId,
        },
      ),
    );
  }

  /// Id for session
  String _generateSessionId() {
    final random = Random();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values).substring(0, 22);
  }

  @override
  void dispose() {
    stop();
    _serverEventController.close();

    // Free the document registry resources
    for (final documentId in _serverRegistry.documentIds) {
      _serverRegistry.getDocument(documentId)?.dispose();
    }
  }
}

/// WebSocket connection
class _WebSocketConnection implements TransportConnection {
  /// Constructor
  _WebSocketConnection(this._webSocket);

  /// The WebSocket
  final WebSocket _webSocket;

  @override
  Stream<List<int>> get incoming => _webSocket.map(
        (data) {
          if (data is String) {
            return utf8.encode(data);
          } else if (data is List<int>) {
            return data;
          } else {
            throw FormatException('Unexpected data type: ${data.runtimeType}');
          }
        },
      );

  @override
  Future<void> send(List<int> data) async {
    _webSocket.add(data);
  }

  @override
  Future<void> close() async {
    await _webSocket.close(normalClosure);
  }

  @override
  bool get isConnected => _webSocket.readyState == WebSocket.open;
}
