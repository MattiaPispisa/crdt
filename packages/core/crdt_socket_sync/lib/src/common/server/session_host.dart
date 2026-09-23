import 'dart:async';
import 'dart:collection';

import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/common/server/client_session.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/common/server/event.dart';
import 'package:crdt_socket_sync/src/common/server/server.dart';
import 'package:crdt_socket_sync/src/plugins/server/server.dart';
import 'package:meta/meta.dart';

/// The lifecycle of a [SessionHostServer].
///
/// `idle` and `stopped` differ only in history: both refuse connections, but
/// `stopped` says the host ran once. `disposed` is terminal.
enum SessionHostState {
  /// Built, never started. Refuses connections unless the host can start
  /// itself (see [SessionHostServer.ownsTransport]).
  idle,

  /// Accepting connections.
  running,

  /// Stopped, and startable again.
  stopped,

  /// Disposed. Terminal: the event stream is closed and nothing restarts.
  disposed,
}

/// {@template session_host_server}
/// A [CRDTSocketServer] that owns **sessions**, not a socket.
///
/// Everything a server does once a peer is connected — keeping the session
/// map, broadcasting, reporting [ServerEvent]s, tearing sessions down — lives
/// here, and none of it mentions a transport. A concrete host supplies the
/// sessions ([createSession]) and the handling of its own protocol's session
/// events ([handleSessionEvent]).
///
/// Connections arrive through [acceptConnection], which is the seam every
/// transport shares: `dart:io` hosts call it after upgrading an `HttpRequest`,
/// and an embedder (an HTTP framework, a test) calls it with whatever
/// [TransportConnection] it already holds.
///
/// ## Plugins are per host
///
/// A [ServerSyncPlugin] binds to the host it is given to, once. Handing the
/// same plugin instance to two hosts throws a `LateInitializationError` far
/// from the line that caused it — build a fresh plugin per host.
/// {@endtemplate}
abstract class SessionHostServer<S extends ClientSession>
    extends CRDTSocketServer {
  /// {@macro session_host_server}
  SessionHostServer({
    Compressor? compressor,
    this.messageCodec,
    this.maxBufferSize,
    super.plugins,
  })  : compressor = compressor ?? NoCompression.instance,
        _serverEventController = StreamController<ServerEvent>.broadcast();

  /// Compressor handed to every session this host creates.
  @protected
  final Compressor compressor;

  /// Message codec handed to every session this host creates.
  ///
  /// `null` lets the session pick the default codec for its mode.
  @protected
  final MessageCodec<Message>? messageCodec;

  /// Maximum outbound buffer size per client session (bytes).
  @protected
  final int? maxBufferSize;

  final Map<String, S> _sessions = {};

  final StreamController<ServerEvent> _serverEventController;

  SessionHostState _state = SessionHostState.idle;

  /// Where this host is in its lifecycle.
  SessionHostState get state => _state;

  /// Whether this host accepts sessions and does its background work.
  ///
  /// It says nothing about a listening socket: a host embedded in another
  /// HTTP server has no socket of its own and is still running.
  bool get isRunning => _state == SessionHostState.running;

  // A getter, not a constructor parameter: a parameter would need an explicit
  // `super(...)` call in every subclass, and Dart forbids mixing that with
  // the `super.plugins` parameter the public constructors already use.
  /// Whether this host owns the transport it serves on.
  ///
  /// `false` (the default) means something else accepts the connections and
  /// hands them over — so [start] binds nothing, and the first
  /// [acceptConnection] starts the host implicitly. `true` means [start] and
  /// [stop] drive a socket through [onStart], [onStarted] and [onStop].
  @protected
  bool get ownsTransport => false;

  /// Active sessions, by id.
  @protected
  Map<String, S> get sessions => UnmodifiableMapView(_sessions);

  /// The session with [id], if this host still holds it.
  @protected
  S? sessionById(String id) => _sessions[id];

  @override
  Stream<ServerEvent> get serverEvents => _serverEventController.stream;

  /// Name of the concrete host, used in diagnostics.
  @protected
  String get debugLabel;

  /// Message of the [ServerEventType.started] event.
  @protected
  String get startedMessage => 'Server started';

  /// Message of the [ServerEventType.stopped] event.
  @protected
  String get stoppedMessage => 'Server stopped';

  /// Message of the [ServerEventType.error] event reported when [start] fails.
  @protected
  String startFailureMessage(Object error) => 'Failed to start server: $error';

  /// Create the session for a newly accepted [connection].
  @protected
  S createSession({
    required String id,
    required TransportConnection connection,
  });

  /// Handle a [SessionEvent] from one of this host's sessions.
  ///
  /// The base handles the events every mode shares ([SessionEventType]).
  /// Overrides deal with their own protocol's events first and forward the
  /// rest with `super.handleSessionEvent(event)`.
  @protected
  FutureOr<void> handleSessionEvent(SessionEvent event) async {
    if (event is SessionEventGeneric) {
      switch (event.type) {
        case SessionEventType.error:
          return handleSessionEventError(event);

        case SessionEventType.pingReceived:
          return handleSessionEventPingReceived(event);

        case SessionEventType.disconnected:
          return handleSessionEventDisconnected(event);
      }
    }
  }

  /// Bring up the transport this host owns. Only called when [ownsTransport].
  ///
  /// Runs before the [ServerEventType.started] event, so anything the event's
  /// message reports (a host and port, say) is already known.
  ///
  /// Throws [UnimplementedError] unless overridden: a host that claims its
  /// transport must also drive it.
  @protected
  Future<void> onStart() async => throw _missingHook('onStart');

  /// Start serving requests. Only called when [ownsTransport].
  ///
  /// Runs after the host is [isRunning], so a connection accepted
  /// synchronously finds a host that is already up.
  ///
  /// Throws [UnimplementedError] unless overridden.
  @protected
  Future<void> onStarted() async => throw _missingHook('onStarted');

  /// Tear down the transport this host owns. Only called when [ownsTransport].
  ///
  /// Throws [UnimplementedError] unless overridden.
  @protected
  Future<void> onStop() async => throw _missingHook('onStop');

  UnimplementedError _missingHook(String hook) {
    return UnimplementedError(
      '[$debugLabel] ownsTransport is true but $hook() is not overridden. '
      'Override onStart(), onStarted() and '
      'onStop() to drive the transport this host owns'
      ' (see IoWebSocketHost)',
    );
  }

  /// Release what this host holds beyond its sessions and plugins.
  ///
  /// Runs while the event stream is still open, so a failure here can still
  /// be reported.
  @protected
  Future<void> onDispose() async {}

  /// Register [connection] as a new session and return it.
  ///
  /// Returns `null` — after closing [connection] — when this host cannot take
  /// it: it was disposed, it was stopped, or [sessionId] is already in use.
  /// Closing is the point: the caller handed over a live socket, and a
  /// refusal that left it open would leak it for the lifetime of the process.
  ///
  /// [sessionId] overrides the generated identifier. Only pass one that is
  /// unguessable — it is echoed to the client and used as a broadcast
  /// identity, so a predictable id lets a peer impersonate another.
  S? acceptConnection(
    TransportConnection connection, {
    String? sessionId,
  }) {
    if (_state == SessionHostState.disposed) {
      // Refused without an event: `dispose` closed `serverEvents`, so there
      // is nobody left to tell. Closing the connection is the part that
      // matters — the caller handed over a live socket.
      unawaited(tryCatchIgnore(connection.close));
      return null;
    }

    if (_state == SessionHostState.stopped) {
      return _refuseConnection(
        connection,
        'the host is stopped',
      );
    }

    if (_state == SessionHostState.idle) {
      if (ownsTransport) {
        // A host that owns its transport cannot be handed a connection before
        // it has started: something is accepting on its behalf.
        return _refuseConnection(connection, 'the host is not started');
      }
      // Embedded in another server: the connection is the start signal.
      _addStartedEvent();
      _state = SessionHostState.running;
    }

    final id = sessionId ?? generateSessionId();

    if (_sessions.containsKey(id)) {
      return _refuseConnection(
        connection,
        'session id $id is already in use',
      );
    }

    final session = createSession(id: id, connection: connection);
    _sessions[id] = session;

    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientConnected,
        message: 'Client connected with session id: $id',
        data: {
          'clientId': id,
        },
      ),
    );

    session.events.listen(
      handleSessionEvent,
      onDone: () {
        handleSessionClosed(id);
      },
      onError: (dynamic error) => handleSessionError(id, error),
    );

    return session;
  }

  /// Closes [connection] and reports the refusal.
  S? _refuseConnection(TransportConnection connection, String reason) {
    unawaited(tryCatchIgnore(connection.close));

    addServerEvent(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Connection refused: $reason',
      ),
    );

    return null;
  }

  @override
  Future<bool> start() async {
    if (_state == SessionHostState.running) {
      return true;
    }

    if (_state == SessionHostState.disposed) {
      // Terminal, and silent for the same reason as a refused connection:
      // `dispose` already closed `serverEvents`.
      return false;
    }

    try {
      if (ownsTransport) {
        await onStart();
      }

      _addStartedEvent();

      _state = SessionHostState.running;

      if (ownsTransport) {
        await onStarted();
      }

      return true;
    } on Exception catch (e) {
      // Only exceptions: a failed bind is reported as an event, a programming
      // error (a missing transport hook, say) must surface.
      addServerEvent(
        ServerEvent(
          type: ServerEventType.error,
          message: startFailureMessage(e),
        ),
      );
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (_state != SessionHostState.running) {
      return;
    }

    _state = SessionHostState.stopped;

    await closeAllSessions();

    if (ownsTransport) {
      await onStop();
    }

    addServerEvent(
      ServerEvent(
        type: ServerEventType.stopped,
        message: stoppedMessage,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await stop();

    for (final plugin in plugins) {
      plugin.dispose();
    }

    // Before the event controller, so a failure to release what the host
    // holds — a registry with writes still waiting, say — still reaches a
    // listener.
    try {
      await onDispose();
    } catch (e) {
      addServerEvent(
        ServerEvent(
          type: ServerEventType.error,
          message: 'Error disposing the host: $e',
        ),
      );
    }

    _state = SessionHostState.disposed;

    unawaited(_serverEventController.close());
  }

  @override
  Future<void> sendMessageToClient(String clientId, Message message) async {
    final session = _sessions[clientId];
    if (session != null) {
      await session.sendMessage(message);
      addServerEvent(
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
        addServerEvent(
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
      addServerEvent(
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

  /// Gracefully close every session.
  ///
  /// Each close is guarded so one failing session does not prevent the others
  /// (and the transport under them) from being torn down.
  @protected
  Future<void> closeAllSessions() async {
    await Future.forEach(
      List.of(_sessions.values),
      (S session) => tryCatchIgnore(session.close),
    );

    _sessions.clear();
  }

  /// Report a session-level error.
  @protected
  void handleSessionEventError(SessionEventGeneric event) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session ${event.sessionId} error: ${event.message}',
        data: event.data,
      ),
    );
  }

  /// Report a ping from a client.
  @protected
  FutureOr<void> handleSessionEventPingReceived(SessionEventGeneric event) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientPingRequest,
        message: 'Session ${event.sessionId} ping request: ${event.message}',
      ),
    );
  }

  /// Report a disconnect and drop the session.
  @protected
  void handleSessionEventDisconnected(SessionEventGeneric event) {
    addServerEvent(
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

  /// Drop a session whose event stream ended.
  @protected
  void handleSessionClosed(String sessionId) {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }

    session.dispose();

    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientDisconnected,
        message: 'Client disconnected with session id: $sessionId',
        data: {
          'clientId': sessionId,
        },
      ),
    );
  }

  /// Report an error on a session's event stream.
  @protected
  void handleSessionError(String sessionId, dynamic error) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.error,
        message: 'Session $sessionId error: $error',
        data: {
          'clientId': sessionId,
        },
      ),
    );
  }

  /// Emit a [ServerEvent] on [serverEvents].
  @protected
  void addServerEvent(ServerEvent event) {
    assert(
      !_serverEventController.isClosed,
      '[$debugLabel] Cannot add new server events'
      ' after the server has been disposed',
    );
    if (_serverEventController.isClosed) {
      return;
    }
    _serverEventController.add(event);
  }

  void _addStartedEvent() {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.started,
        message: startedMessage,
      ),
    );
  }
}
