import 'dart:async';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';
import 'package:crdt_socket_sync/src/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server/registry.dart';

/// Client session on server
///
/// - Handle incoming messages from [_connection]
/// - Send messages using [_connection]
class ClientSession {
  /// Constructor
  ClientSession({
    required this.id,
    required TransportConnection connection,
    required CRDTServerRegistry serverRegistry,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    List<ServerSyncPlugin> plugins = const [],
  })  : _isClosed = false,
        _connection = connection,
        _serverRegistry = serverRegistry,
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

  /// The server registry
  final CRDTServerRegistry _serverRegistry;

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

  /// Client peer ID
  PeerId? _clientAuthor;

  /// The documents the client is subscribed to
  final Set<String> _subscribedDocuments = {};

  /// The documents the client is subscribed to
  List<String> get subscribedDocuments => _subscribedDocuments.toList();

  /// Message codec
  final MessageCodec<Message> _messageCodec;

  /// Send a message to the client
  Future<void> sendMessage(Message message) async {
    if (_isClosed) {
      return _addSessionEvent(
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
        _addSessionEvent(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.error,
            message: 'Failed to encode message: $message. '
                'This message is not supported by any plugin.',
          ),
        );
        return;
      }

      await _connection.send(data);
    } catch (e) {
      _addSessionEvent(
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
        _addSessionEvent(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.error,
            message: 'Failed to decode message: $data. '
                'This message is not supported by any plugin.',
          ),
        );
        return;
      }
      _handleMessage(message);
    } catch (e, stackTrace) {
      _addSessionEvent(
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

    _addSessionEvent(
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
      switch (message.type) {
        case MessageType.handshakeRequest:
          return await _handleHandshakeRequest(
            message as HandshakeRequestMessage,
          );

        case MessageType.change:
          final changeMessage = message as ChangeMessage;
          return await _handleChangesMessage(
            changes: [changeMessage.change],
            documentId: changeMessage.documentId,
          );

        case MessageType.changes:
          final changesMessage = message as ChangesMessage;
          return await _handleChangesMessage(
            changes: changesMessage.changes,
            documentId: changesMessage.documentId,
          );

        case MessageType.documentStatusRequest:
          return await _handleDocumentStatusRequest(
            message as DocumentStatusRequestMessage,
          );

        case MessageType.ping:
          return await _handlePingMessage(message as PingMessage);

        case MessageType.pong:
        case MessageType.handshakeResponse:
        case MessageType.error:
        case MessageType.documentStatus:
          break;
      }
    } catch (e) {
      _addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to handle message: $e',
        ),
      );
    }
  }

  /// Handle handshake
  Future<void> _handleHandshakeRequest(HandshakeRequestMessage message) async {
    final documentId = message.documentId;
    final hasDocument = await _serverRegistry.hasDocument(documentId);

    if (!hasDocument) {
      // send error message if the document does not exist
      return sendMessage(
        Message.error(
          documentId: documentId,
          code: Protocol.errorDocumentNotFound,
          message: 'Document not found: $documentId',
        ),
      );
    }

    _clientAuthor = message.author;
    _subscribedDocuments.add(documentId);

    for (final plugin in _plugins) {
      plugin.onDocumentRegistered(this, documentId);
    }

    final document = (await _serverRegistry.getDocument(documentId))!;
    final snapshot = await _serverRegistry.getLatestSnapshot(documentId);

    // Use exportChangesNewerThan to get changes newer than client's version
    late List<Change> changes;
    changes = document.exportChangesNewerThan(message.versionVector);

    // Get the server's version vector representing the state 
    // after snapshot and changes
    final serverVersionVector = document.getVersionVector();

    final response = HandshakeResponseMessage(
      documentId: documentId,
      changes: changes,
      snapshot: snapshot,
      sessionId: id,
      versionVector: serverVersionVector,
    );

    await sendMessage(response);

    _addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.handshakeCompleted,
        message: 'Handshake completed for document $documentId',
        data: {
          'documentId': documentId,
          'peerId': _clientAuthor.toString(),
        },
      ),
    );
  }

  Future<void> _handleChangesMessage({
    required List<Change> changes,
    required String documentId,
  }) async {
    final hasDocument = await _serverRegistry.hasDocument(documentId);

    if (!hasDocument) {
      _addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Document not found: $documentId'
              ', cannot apply changes ${changes.map((c) => c.id).join(', ')}',
        ),
      );
      return;
    }

    if (!isSubscribedTo(documentId)) {
      _addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Client is not subscribed to document: $documentId'
              ', cannot apply changes ${changes.map((c) => c.id).join(', ')}',
        ),
      );
      return;
    }

    for (final change in changes) {
      try {
        final applied = await _serverRegistry.applyChange(documentId, change);

        if (applied) {
          _addSessionEvent(
            SessionEventChangeApplied(
              sessionId: id,
              message: 'Change received and applied for document $documentId',
              documentId: documentId,
              change: change,
            ),
          );
        } else {
          _addSessionEvent(
            SessionEventGeneric(
              sessionId: id,
              type: SessionEventType.error,
              message: 'Failed to apply change ${change.id}',
            ),
          );
        }
      } on CausallyNotReadyException {
        await sendMessage(
          Message.error(
            documentId: documentId,
            code: Protocol.errorOutOfSync,
            message: 'Client is out of sync. Please re-sync.',
          ),
        );
        _addSessionEvent(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.clientOutOfSync,
            message: 'Client is out of sync. Please re-sync.',
          ),
        );
      } catch (e) {
        _addSessionEvent(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.error,
            message: 'Failed to apply change ${change.id}: $e',
          ),
        );
      }
    }
  }

  /// Handle snapshot request
  Future<void> _handleDocumentStatusRequest(
    DocumentStatusRequestMessage message,
  ) async {
    final documentId = message.documentId;
    final hasDocument = await _serverRegistry.hasDocument(documentId);

    if (!hasDocument) {
      // send error message if the document does not exist
      _addSessionEvent(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Document not found: $documentId'
              ', cannot send snapshot',
        ),
      );
      return sendMessage(
        Message.error(
          documentId: documentId,
          code: Protocol.errorDocumentNotFound,
          message: 'Document not found: $documentId',
        ),
      );
    }

    if (!isSubscribedTo(documentId)) {
      _subscribedDocuments.add(documentId);
    }

    final snapshot = await _serverRegistry.getLatestSnapshot(documentId);
    
    // Use exportChangesNewerThan to get changes newer than client's version
    final document = (await _serverRegistry.getDocument(documentId))!;
    late List<Change> changes;
    if (message.versionVector != null) {
      changes = document.exportChangesNewerThan(message.versionVector!);
    } else {
      changes = document.exportChanges();
    }

    // Get the server's version vector representing the state after snapshot and changes
    final serverVersionVector = document.getVersionVector();

    final response = Message.documentStatus(
      documentId: documentId,
      snapshot: snapshot,
      changes: changes,
      versionVector: serverVersionVector,
    );
    await sendMessage(response);

    _addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.documentStatusCreated,
        message: 'Snapshot request completed for document $documentId',
        data: {
          'documentId': documentId,
          'peerId': _clientAuthor.toString(),
        },
      ),
    );
  }

  Future<void> _handlePingMessage(PingMessage message) async {
    final pongMessage = Message.pong(
      documentId: message.documentId,
      originalTimestamp: message.timestamp,
      responseTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await sendMessage(pongMessage);

    _addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.pingReceived,
        message: 'Ping received from client',
      ),
    );
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

    _addSessionEvent(
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

    for (final plugin in _plugins) {
      plugin.onSessionClosed(this);
    }

    _addSessionEvent(
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

  void _addSessionEvent(SessionEvent event) {
    if (_sessionEventController.isClosed) {
      return;
    }
    _sessionEventController.add(event);
  }
}
