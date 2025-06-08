import 'dart:async';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';
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
  })  : _connection = connection,
        _serverRegistry = serverRegistry,
        _sessionEventController = StreamController<SessionEvent>.broadcast(),
        _messageCodec = CompressedCodec<Message>(
          JsonMessageCodec<Message>(
            toJson: (message) => message.toJson(),
            fromJson: Message.fromJson,
          ),
          compressor: compressor ?? NoCompression.instance,
        ) {
    _connection.incoming.listen(
      _handleData,
      onError: _handleConnectionError,
      onDone: _handleConnectionClosed,
    );

    _startHeartbeatMonitoring();
  }

  /// Session ID
  final String id;

  /// The transport for the communication with the client
  final TransportConnection _connection;

  /// The server registry
  final CRDTServerRegistry _serverRegistry;

  /// Session event controller
  final StreamController<SessionEvent> _sessionEventController;

  /// Timer for monitoring client heartbeat
  Timer? _heartbeatTimer;

  /// Last time we received any message from client
  DateTime _lastClientActivity = DateTime.now();

  /// Whether the session is closed
  bool _isClosed = false;

  /// Session events stream
  Stream<SessionEvent> get events => _sessionEventController.stream;

  /// Client peer ID
  PeerId? _clientAuthor;

  /// The documents the client is subscribed to
  final Set<String> _subscribedDocuments = {};

  /// Message codec
  final MessageCodec<Message> _messageCodec;

  /// Send a message to the client
  Future<void> sendMessage(Message message) async {
    if (_isClosed) {
      return _sessionEventController.add(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Session is closed',
        ),
      );
    }

    try {
      final data = _messageCodec.encode(message);
      await _connection.send(data);
    } catch (e) {
      _sessionEventController.add(
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
    // Update last activity timestamp
    _lastClientActivity = DateTime.now();

    try {
      final message = _messageCodec.decode(data);
      _handleMessage(message);
    } catch (e, stackTrace) {
      _sessionEventController.add(
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

    _sessionEventController.add(
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
    try {
      switch (message.type) {
        case MessageType.handshakeRequest:
          return await _handleHandshakeRequest(
            message as HandshakeRequestMessage,
          );

        case MessageType.change:
          return _handleChangeMessage(message as ChangeMessage);

        case MessageType.snapshotRequest:
          return await _handleSnapshotRequest(
            message as SnapshotRequestMessage,
          );

        case MessageType.ping:
          return await _handlePingMessage(message as PingMessage);

        case MessageType.pong:
        case MessageType.handshakeResponse:
        case MessageType.error:
        case MessageType.snapshot:
          break;
      }
    } catch (e) {
      _sessionEventController.add(
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

    if (!_serverRegistry.hasDocument(documentId)) {
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

    final document = _serverRegistry.getDocument(documentId)!;
    final snapshot = _serverRegistry.getLatestSnapshot(documentId);

    late List<Change> changes;

    try {
      changes = document.exportChanges(from: message.version);
    } catch (e) {
      // goes here if the client is out of sync with the server
      changes = document.exportChanges();
    }

    final response = HandshakeResponseMessage(
      documentId: documentId,
      changes: changes,
      snapshot: snapshot,
    );

    await sendMessage(response);

    _sessionEventController.add(
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

  void _handleChangeMessage(ChangeMessage message) {
    final documentId = message.documentId;

    if (!_serverRegistry.hasDocument(documentId)) {
      _sessionEventController.add(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Document not found: $documentId'
              ', cannot apply change ${message.change.id}',
        ),
      );
      return;
    }

    if (!isSubscribedTo(documentId)) {
      _sessionEventController.add(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Client is not subscribed to document: $documentId'
              ', cannot apply change ${message.change.id}',
        ),
      );
      return;
    }

    try {
      final applied = _serverRegistry.applyChange(documentId, message.change);

      if (applied) {
        _sessionEventController.add(
          SessionEventChangeApplied(
            sessionId: id,
            message: 'Change received and applied for document $documentId',
            documentId: documentId,
            change: message.change,
          ),
        );
      } else {
        _sessionEventController.add(
          SessionEventGeneric(
            sessionId: id,
            type: SessionEventType.error,
            message: 'Failed to apply change ${message.change.id}',
          ),
        );
      }
    } catch (e) {
      _sessionEventController.add(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to apply change ${message.change.id}: $e',
        ),
      );
    }
  }

  /// Handle snapshot request
  Future<void> _handleSnapshotRequest(SnapshotRequestMessage message) async {
    final documentId = message.documentId;

    if (!_serverRegistry.hasDocument(documentId)) {
      // send error message if the document does not exist
      _sessionEventController.add(
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

    final snapshot = _serverRegistry.createSnapshot(documentId);

    final response = Message.snapshot(
      documentId: documentId,
      snapshot: snapshot,
    );
    await sendMessage(response);

    _sessionEventController.add(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.snapshotCreated,
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

    _sessionEventController.add(
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

    _sessionEventController.add(
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

  /// Close the session with reason
  void _closeSession({
    required String reason,
  }) {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _stopHeartbeatMonitoring();

    _sessionEventController.add(
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
}
