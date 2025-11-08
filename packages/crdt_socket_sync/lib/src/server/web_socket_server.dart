import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/server/client_session.dart';
import 'package:crdt_socket_sync/src/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server/event.dart';
import 'package:crdt_socket_sync/src/server/registry.dart';
import 'package:crdt_socket_sync/src/server/server.dart';
import 'package:web_socket_channel/status.dart';

// TODO(mattia): A system that is client session aware
// and can perform snapshot when all clients are aligned.
// Maybe in a plugin only for the server?

/// WebSocket server implementation
class WebSocketServer extends CRDTSocketServer {
  /// Constructor
  WebSocketServer({
    required Future<HttpServer> Function() serverFactory,
    required CRDTServerRegistry serverRegistry,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer = _DefaultWebSocketTransformerWrapper(),
        _compressor = compressor ?? NoCompression.instance,
        _serverEventController = StreamController<ServerEvent>.broadcast(),
        _serverRegistry = serverRegistry,
        _messageCodec = messageCodec;

  /// Constructor for testing
  WebSocketServer.test({
    required Future<HttpServer> Function() serverFactory,
    required CRDTServerRegistry serverRegistry,
    Compressor? compressor,
    WebSocketServerTransformer? serverTransformer,
    MessageCodec<Message>? messageCodec,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer =
            serverTransformer ?? _DefaultWebSocketTransformerWrapper(),
        _compressor = compressor ?? NoCompression.instance,
        _serverEventController = StreamController<ServerEvent>.broadcast(),
        _serverRegistry = serverRegistry,
        _messageCodec = messageCodec;

  /// The document registry
  final CRDTServerRegistry _serverRegistry;

  /// The server transformer
  final WebSocketServerTransformer _serverTransformer;

  final Future<HttpServer> Function() _serverFactory;

  /// The server
  HttpServer? _server;

  /// The server host, if the server is not running, it will return `''`
  String get host => _server?.address.host ?? '';

  /// The server port, if the server is not running, it will return `0`
  int get port => _server?.port ?? 0;

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

  /// Message codec to use
  final MessageCodec<Message>? _messageCodec;

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
      _server = await _serverFactory();

      _addServerEvent(
        ServerEvent(
          type: ServerEventType.started,
          message: 'Server started on $host:$port',
        ),
      );

      _isRunning = true;

      _server!.listen((request) {
        if (_serverTransformer.isUpgradeRequest(request)) {
          _serverTransformer.upgrade(request).then(_handleWebSocket);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.close();
        }
      });

      return true;
    } catch (e) {
      _addServerEvent(
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
    await Future.forEach(
      _sessions.values,
      (ClientSession session) => session.close,
    );

    _sessions.clear();

    await _server?.close();
    _server = null;

    _addServerEvent(
      const ServerEvent(
        type: ServerEventType.stopped,
        message: 'Server stopped',
      ),
    );
  }

  @override
  Future<void> sendMessageToClient(String clientId, Message message) async {
    final session = _sessions[clientId];
    if (session != null) {
      await session.sendMessage(message);
      _addServerEvent(
        ServerEvent(
          type: ServerEventType.messageSent,
          message: 'Message sent to client $clientId',
          data: {
            'clientId': clientId,
          },
        ),
      );
    }
  }

  @override
  Future<void> broadcastMessage(
    Message message, {
    List<String>? excludeClientIds,
  }) async {
    final documentId = message.documentId;
    final sessions = List.of(_sessions.values);

    final sessionsReached = <String>[];

    for (final session in sessions) {
      final isExcluded = excludeClientIds?.contains(session.id) ?? false;
      final isSubscribed = session.isSubscribedTo(documentId);

      if (!isExcluded && isSubscribed) {
        await session.sendMessage(message);
        sessionsReached.add(session.id);
      }
    }

    if (sessionsReached.isNotEmpty) {
      _addServerEvent(
        ServerEvent(
          type: ServerEventType.messageBroadcasted,
          message: 'Message broadcasted to ${sessionsReached.length} clients',
          data: {
            'documentId': documentId,
            'sessionsReached': sessionsReached,
            'message': message.toJson(),
          },
        ),
      );
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
      plugins: plugins,
      messageCodec: _messageCodec,
    );

    _sessions[sessionId] = session;

    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientConnected,
        message: 'Client connected with session id: $sessionId',
        data: {
          'clientId': sessionId,
        },
      ),
    );

    session.events.listen(
      _handleSessionEvent,
      onDone: () {
        _handleSessionClosed(sessionId);
      },
      onError: (dynamic error) => _handleSessionError(sessionId, error),
    );
  }

  /// Add a server event for a handshake completed event
  void _handleSessionEventHandshakeCompleted(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientHandshake,
        message:
            'Session ${event.sessionId} handshake completed: ${event.message}',
        data: event.data,
      ),
    );
  }

  /// 1. Add a server event for the change applied
  /// 1. Broadcast the change to the other clients
  Future<void> _handleSessionEventChangeApplied(
    SessionEventChangeApplied event,
  ) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientChangeApplied,
        message: 'Session ${event.sessionId} change applied: ${event.message}',
      ),
    );
    return broadcastMessage(
      Message.change(
        documentId: event.documentId,
        change: event.change,
      ),
      excludeClientIds: [event.sessionId],
    );
  }

  /// Add a server event for an error event
  void _handleSessionEventError(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session ${event.sessionId} error: ${event.message}',
        data: event.data,
      ),
    );
  }

  /// Add a server event for a client out of sync event
  void _handleSessionEventClientOutOfSync(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientOutOfSync,
        message: 'Session ${event.sessionId} out of sync: ${event.message}',
      ),
    );
  }

  /// Handle a [ClientSession] event.
  FutureOr<void> _handleSessionEvent(SessionEvent event) async {
    switch (event.type) {
      case SessionEventType.handshakeCompleted:
        return _handleSessionEventHandshakeCompleted(
          event as SessionEventGeneric,
        );

      case SessionEventType.changeApplied:
        return _handleSessionEventChangeApplied(
          event as SessionEventChangeApplied,
        );

      case SessionEventType.error:
        return _handleSessionEventError(
          event as SessionEventGeneric,
        );

      case SessionEventType.documentStatusCreated:
        return _handleSessionEventDocumentStatusRequest(
          event as SessionEventGeneric,
        );

      case SessionEventType.pingReceived:
        return _handleSessionEventPingReceived(
          event as SessionEventGeneric,
        );

      case SessionEventType.disconnected:
        return _handleSessionEventDisconnected(
          event as SessionEventGeneric,
        );

      case SessionEventType.clientOutOfSync:
        return _handleSessionEventClientOutOfSync(
          event as SessionEventGeneric,
        );
    }
  }

  /// Add a server event for a document status request event
  void _handleSessionEventDocumentStatusRequest(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientDocumentStatusCreated,
        message: 'Session ${event.sessionId} document'
            ' status request: ${event.message}',
      ),
    );
  }

  /// Add a server event for a ping received event
  void _handleSessionEventPingReceived(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientPingRequest,
        message: 'Session ${event.sessionId} ping request: ${event.message}',
      ),
    );
  }

  /// 1. Add a server event for a client disconnected event
  /// 1. Dispose the session
  void _handleSessionEventDisconnected(SessionEventGeneric event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientDisconnected,
        message: 'Session ${event.sessionId} disconnected: ${event.message}',
      ),
    );
    final session = _sessions[event.sessionId];
    if (session == null) {
      return;
    }

    session.dispose();
    _sessions.remove(event.sessionId);
  }

  /// Handle session closed
  void _handleSessionClosed(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }

    session.dispose();

    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientDisconnected,
        message: 'Client disconnected with session id: $sessionId',
        data: {
          'clientId': sessionId,
        },
      ),
    );
  }

  /// Handle session error
  void _handleSessionError(String sessionId, dynamic error) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session $sessionId error: $error',
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
  Future<void> dispose() async {
    await stop();
    unawaited(_serverEventController.close());

    for (final plugin in plugins) {
      plugin.dispose();
    }

    final documentIds = await _serverRegistry.documentIds;

    // Free the document registry resources
    for (final documentId in documentIds) {
      try {
        final document = await _serverRegistry.getDocument(documentId);
        if (document != null) {
          document.dispose();
        }
      } catch (e) {
        _addServerEvent(
          ServerEvent(
            type: ServerEventType.error,
            message: 'Error disposing document: $e',
            data: {
              'documentId': documentId,
            },
          ),
        );
      }
    }
  }

  void _addServerEvent(ServerEvent event) {
    assert(
      !_serverEventController.isClosed,
      '[WebSocketServer] Cannot add new server events'
      ' after the server has been disposed',
    );
    if (_serverEventController.isClosed) {
      return;
    }
    _serverEventController.add(event);
  }
}

/// WebSocket connection
class _WebSocketConnection implements TransportConnection {
  /// Constructor
  _WebSocketConnection(this._webSocket);

  /// The WebSocket
  final WebSocket _webSocket;

  @override
  Stream<List<int>> get incoming {
    return _webSocket.map(
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
  }

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

/// WebSocket server transformer
abstract class WebSocketServerTransformer {
  /// Check if the request is an upgrade request
  bool isUpgradeRequest(HttpRequest request);

  /// Upgrade the request to a WebSocket connection
  Future<WebSocket> upgrade(HttpRequest request);
}

class _DefaultWebSocketTransformerWrapper
    implements WebSocketServerTransformer {
  @override
  bool isUpgradeRequest(HttpRequest request) {
    return WebSocketTransformer.isUpgradeRequest(request);
  }

  @override
  Future<WebSocket> upgrade(HttpRequest request) {
    return WebSocketTransformer.upgrade(request);
  }
}
