import 'dart:async';

import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';
import 'package:meta/meta.dart';

/// Client session on server
///
/// Shared, protocol-agnostic machinery for a single connected client:
///
/// - Handle incoming messages from the [TransportConnection]
/// - Send messages using the [TransportConnection] through a bounded
///   [OutboundQueue]
/// - Monitor client liveness ([Protocol.clientTimeout])
/// - Dispatch messages and lifecycle hooks to the [ServerSyncPlugin]s
///
/// Concrete sessions implement [handleTypedMessage] with the
/// protocol-specific message handling.
abstract class ClientSession {
  /// Base constructor for concrete sessions.
  ClientSession.base({
    required this.id,
    required TransportConnection connection,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    int? maxBufferSize,
    List<ServerSyncPlugin> plugins = const [],
  })  : _isClosed = false,
        _connection = connection,
        _plugins = plugins,
        _sessionEventController = StreamController<SessionEvent>.broadcast(),
        _messageCodec = CompressedCodec<Message>(
          PluginAwareMessageCodec.fromPlugins(
            plugins: plugins,
            defaultCodec: messageCodec ??
                JsonMessageCodec<Message>(
                  toJson: (message) => message.toJson(),
                  fromJson: Message.fromJson,
                ),
          ),
          compressor: compressor ?? NoCompression.instance,
        ) {
    _outboundQueue = OutboundQueue(
      onSend: _connection.send,
      maxBufferSize: maxBufferSize ?? Protocol.maxBufferSize,
    );
    _updateClientActivity();
    _connection.incoming.listen(
      _handleData,
      onError: _handleConnectionError,
      onDone: _handleConnectionClosed,
    );

    _startHeartbeatMonitoring();
    for (final plugin in _plugins) {
      plugin.onNewSession(this);
    }
  }

  /// Session ID
  final String id;

  /// The transport for the communication with the client
  final TransportConnection _connection;

  /// The plugins to use for this session
  final List<ServerSyncPlugin> _plugins;

  /// Session event controller
  final StreamController<SessionEvent> _sessionEventController;

  /// Timer for monitoring client heartbeat
  Timer? _heartbeatTimer;

  /// Last time we received any message from client
  late DateTime _lastClientActivity;

  /// Whether the session is closed
  bool _isClosed;

  /// Session events stream
  Stream<SessionEvent> get events => _sessionEventController.stream;

  /// The documents the client is subscribed to
  final Set<String> _subscribedDocuments = {};

  /// The documents the client is subscribed to
  List<String> get subscribedDocuments => _subscribedDocuments.toList();

  /// Message codec
  final MessageCodec<Message> _messageCodec;

  /// Bounded, serialized outbound send queue.
  late final OutboundQueue _outboundQueue;

  /// Send a message to the client
  Future<void> sendMessage(Message message) async {
    if (_isClosed) {
      return addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Session is closed',
        ),
      );
    }

    try {
      final data = _messageCodec.encode(message);

      if (data == null) {
        addSessionEvent(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.error,
            message: 'Failed to encode message: $message. '
                'This message is not supported by any plugin.',
          ),
        );
        return;
      }

      await _outboundQueue.add(data);
    } catch (e) {
      addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to send message: $e',
        ),
      );

      // If we can't send, assume connection is dead
      _closeSession(reason: 'Failed to send message: $e');
      rethrow;
    }
  }

  /// Close the session
  Future<void> close() async {
    _closeSession(reason: 'Session manually closed');
    await tryCatchIgnore(_connection.close);
  }

  /// Handle incoming data from the transport
  void _handleData(List<int> data) {
    _updateClientActivity();

    try {
      final message = _messageCodec.decode(data);
      if (message == null) {
        handleUndecodable(data);
        return;
      }
      _handleMessage(message);
    } catch (e, stackTrace) {
      addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to decode message: $e',
          data: {
            'stackTrace': stackTrace,
          },
        ),
      );
    }
  }

  /// Handle connection error
  void _handleConnectionError(dynamic error) {
    if (_isClosed) {
      return;
    }

    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.error,
        message: 'Connection error: $error',
      ),
    );

    // Close the session on connection error
    _closeSession(reason: 'Connection error: $error');
  }

  /// Handle connection closed
  void _handleConnectionClosed() {
    if (_isClosed) {
      return;
    }

    _closeSession(reason: 'Client disconnected');
  }

  /// Handle incoming message
  Future<void> _handleMessage(Message message) async {
    if (_isClosed) {
      return;
    }

    for (final plugin in _plugins) {
      plugin.onMessage(this, message);
    }

    try {
      await handleTypedMessage(message);
    } catch (e) {
      addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to handle message: $e',
        ),
      );
    }
  }

  /// Handle a protocol [message], after plugin dispatch.
  ///
  /// Implementations should ignore message types they do not handle.
  /// Thrown errors are reported as [SessionEventType.error] events.
  @protected
  Future<void> handleTypedMessage(Message message);

  /// Called for an incoming [data] frame no codec could decode.
  ///
  /// The default reports a [SessionEventType.error] event. Sessions may
  /// override it to answer the peer (for example, a relay session diagnoses a
  /// CRDT-aware sync client that connected to the wrong server).
  @protected
  void handleUndecodable(List<int> data) {
    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.error,
        message: 'Failed to decode message: $data. '
            'This message is not supported by any plugin.',
      ),
    );
  }

  /// Mark this session as subscribed to [documentId].
  ///
  /// When [notifyPlugins] is `true`, fires
  /// [ServerSyncPlugin.onDocumentRegistered] for every plugin.
  @protected
  void registerDocument(String documentId, {bool notifyPlugins = true}) {
    _subscribedDocuments.add(documentId);
    if (!notifyPlugins) {
      return;
    }
    for (final plugin in _plugins) {
      plugin.onDocumentRegistered(this, documentId);
    }
  }

  /// Check if the client is subscribed to [documentId]
  bool isSubscribedTo(String documentId) {
    return _subscribedDocuments.contains(documentId);
  }

  /// Start heartbeat monitoring
  ///
  /// Controls that the client is still alive
  /// by checking if the client has sent a message
  /// in the last [Protocol.clientTimeout]
  void _startHeartbeatMonitoring() {
    _stopHeartbeatMonitoring();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkClientHeartbeat(),
    );
  }

  /// Stop heartbeat monitoring
  void _stopHeartbeatMonitoring() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Check if client is still alive based on last activity
  void _checkClientHeartbeat() {
    if (_isClosed) {
      return;
    }

    final timeSinceLastActivity =
        DateTime.now().difference(_lastClientActivity);

    if (timeSinceLastActivity <= Protocol.clientTimeout) {
      return;
    }

    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.error,
        message: 'Client timeout - no activity for'
            ' ${timeSinceLastActivity.inSeconds}s',
        data: {
          'timeoutThreshold': Protocol.clientTimeout.inSeconds,
          'lastActivity': _lastClientActivity.toIso8601String(),
        },
      ),
    );

    _closeSession(reason: 'Client timeout');
  }

  /// Update last activity timestamp
  void _updateClientActivity() {
    _lastClientActivity = DateTime.now();
  }

  /// Close the session with reason
  void _closeSession({
    required String reason,
  }) {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _stopHeartbeatMonitoring();
    _outboundQueue.close();

    for (final plugin in _plugins) {
      plugin.onSessionClosed(this);
    }

    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.disconnected,
        message: reason,
        data: {
          'lastActivity': _lastClientActivity.toIso8601String(),
          'sessionDuration':
              DateTime.now().difference(_lastClientActivity).inSeconds,
        },
      ),
    );
  }

  /// Dispose the session
  void dispose() {
    _closeSession(reason: 'Session disposed');
    _sessionEventController.close();
  }

  /// Emit a [SessionEvent] on [events].
  @protected
  void addSessionEvent(SessionEvent event) {
    if (_sessionEventController.isClosed) {
      return;
    }
    _sessionEventController.add(event);
  }
}
