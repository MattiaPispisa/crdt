import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/common/server/event.dart';
import 'package:crdt_socket_sync/src/common/server/server.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/io_connection.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/transformer.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:crdt_socket_sync/src/relay/server/compaction.dart';
import 'package:crdt_socket_sync/src/relay/server/in_memory_relay_store.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_client_session.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_session_event.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';

/// {@template web_socket_relay_server}
/// WebSocket relay server implementation.
///
/// A relay server rebroadcasts opaque CRDT change blobs to the other clients
/// of a room and persists them in a [RelayStore], without ever interpreting
/// CRDT data: merging is entirely a client concern. One server hosts many
/// rooms, keyed by document id.
/// {@endtemplate}
class WebSocketRelayServer extends CRDTSocketServer {
  /// {@macro web_socket_relay_server}
  ///
  /// Constructor
  WebSocketRelayServer({
    required Future<HttpServer> Function() serverFactory,
    RelayStore? store,
    RelayCompactionCoordinator? compaction,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    int? maxBufferSize,
    List<ServerSyncPlugin>? plugins,
  }) : this._(
          serverFactory: serverFactory,
          serverTransformer: DefaultWebSocketServerTransformer(),
          store: store,
          compaction: compaction,
          compressor: compressor,
          messageCodec: messageCodec,
          maxBufferSize: maxBufferSize,
          plugins: plugins,
        );

  /// {@macro web_socket_relay_server}
  ///
  /// Constructor for testing
  WebSocketRelayServer.test({
    required Future<HttpServer> Function() serverFactory,
    WebSocketServerTransformer? serverTransformer,
    RelayStore? store,
    RelayCompactionCoordinator? compaction,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    int? maxBufferSize,
    List<ServerSyncPlugin>? plugins,
  }) : this._(
          serverFactory: serverFactory,
          serverTransformer:
              serverTransformer ?? DefaultWebSocketServerTransformer(),
          store: store,
          compaction: compaction,
          compressor: compressor,
          messageCodec: messageCodec,
          maxBufferSize: maxBufferSize,
          plugins: plugins,
        );

  WebSocketRelayServer._({
    required Future<HttpServer> Function() serverFactory,
    required WebSocketServerTransformer serverTransformer,
    RelayStore? store,
    RelayCompactionCoordinator? compaction,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    int? maxBufferSize,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer = serverTransformer,
        _store = store ?? InMemoryRelayStore(),
        _compaction = compaction ?? RelayCompactionCoordinator(),
        _compressor = compressor ?? NoCompression.instance,
        _serverEventController = StreamController<ServerEvent>.broadcast(),
        _messageCodec = messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: (json) =>
                  RelayMessage.fromJson(json) ?? Message.fromJson(json),
            ),
        _maxBufferSize = maxBufferSize;

  /// The room persistence
  final RelayStore _store;

  /// The room persistence used by this server.
  RelayStore get store => _store;

  /// The compaction coordinator, shared across sessions
  final RelayCompactionCoordinator _compaction;

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
  final Map<String, RelayClientSession> _sessions = {};

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
  final MessageCodec<Message> _messageCodec;

  /// Maximum outbound buffer size per client session (bytes).
  final int? _maxBufferSize;

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
          message: 'Relay server started on $host:$port',
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
          message: 'Failed to start relay server: $e',
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

    // Gracefully close every session. Guard each close so one failing
    // session does not prevent the others (and the server socket) from
    // being torn down.
    await Future.forEach(
      List.of(_sessions.values),
      (RelayClientSession session) => tryCatchIgnore(session.close),
    );

    _sessions.clear();

    await _server?.close();
    _server = null;

    _addServerEvent(
      const ServerEvent(
        type: ServerEventType.stopped,
        message: 'Relay server stopped',
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

      if (isExcluded || !isSubscribed) {
        continue;
      }

      try {
        await session.sendMessage(message);
        sessionsReached.add(session.id);
      } catch (e) {
        // A failing client must not prevent the broadcast from reaching the
        // remaining healthy clients. `sendMessage` already closed the failing
        // session; just record the error and continue.
        _addServerEvent(
          ServerEvent(
            type: ServerEventType.error,
            message: 'Failed to broadcast to session ${session.id}: $e',
            data: {
              'clientId': session.id,
              'documentId': documentId,
            },
          ),
        );
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
  /// 1. create a new [RelayClientSession]
  void _handleWebSocket(WebSocket webSocket) {
    // Generate a unique session ID
    final sessionId = generateSessionId();

    final connection = IoWebSocketConnection(webSocket);

    final session = RelayClientSession(
      id: sessionId,
      connection: connection,
      store: _store,
      compaction: _compaction,
      compressor: _compressor,
      plugins: plugins,
      messageCodec: _messageCodec,
      maxBufferSize: _maxBufferSize,
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

  /// Handle a [RelayClientSession] event.
  FutureOr<void> _handleSessionEvent(SessionEvent event) async {
    if (event is RelaySessionEvent) {
      switch (event.type) {
        case RelaySessionEventType.relayJoined:
          return _handleSessionEventJoined(event as RelaySessionEventJoined);

        case RelaySessionEventType.relayChangesPushed:
          return _handleSessionEventChangesPushed(
            event as RelaySessionEventChangesPushed,
          );

        case RelaySessionEventType.relaySnapshotUploaded:
          return _handleSessionEventSnapshotUploaded(
            event as RelaySessionEventSnapshotUploaded,
          );
      }
    }

    if (event is SessionEventGeneric) {
      switch (event.type) {
        case SessionEventType.error:
          return _handleSessionEventError(event);

        case SessionEventType.pingReceived:
          return _handleSessionEventPingReceived(event);

        case SessionEventType.disconnected:
          return _handleSessionEventDisconnected(event);
      }
    }
  }

  /// Add a server event for a relay join event
  void _handleSessionEventJoined(RelaySessionEventJoined event) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientHandshake,
        message: 'Session ${event.sessionId} joined: ${event.message}',
        data: {
          'clientId': event.sessionId,
          'documentId': event.documentId,
          'peerId': event.author.toString(),
        },
      ),
    );
  }

  /// 1. Add a server event for the pushed changes
  /// 1. Rebroadcast the change blobs to the other clients in the room
  Future<void> _handleSessionEventChangesPushed(
    RelaySessionEventChangesPushed event,
  ) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.clientChangeApplied,
        message: 'Session ${event.sessionId} pushed: ${event.message}',
        data: {
          'clientId': event.sessionId,
          'documentId': event.documentId,
          'seq': event.seq,
        },
      ),
    );
    return broadcastMessage(
      RelayChangesMessage(
        documentId: event.documentId,
        changes: event.changes,
        seq: event.seq,
        from: event.sessionId,
      ),
      excludeClientIds: [event.sessionId],
    );
  }

  /// Add a server event for an uploaded snapshot
  void _handleSessionEventSnapshotUploaded(
    RelaySessionEventSnapshotUploaded event,
  ) {
    _addServerEvent(
      ServerEvent(
        type: ServerEventType.snapshotCreated,
        message: 'Session ${event.sessionId} compacted: ${event.message}',
        data: {
          'clientId': event.sessionId,
          'documentId': event.documentId,
          'upToSeq': event.upToSeq,
        },
      ),
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

  @override
  Future<void> dispose() async {
    await stop();
    unawaited(_serverEventController.close());

    for (final plugin in plugins) {
      plugin.dispose();
    }
  }

  void _addServerEvent(ServerEvent event) {
    assert(
      !_serverEventController.isClosed,
      '[WebSocketRelayServer] Cannot add new server events'
      ' after the server has been disposed',
    );
    if (_serverEventController.isClosed) {
      return;
    }
    _serverEventController.add(event);
  }
}
