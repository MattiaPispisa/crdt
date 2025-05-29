import 'dart:async';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';
import 'package:crdt_socket_sync/src/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server/registry.dart';

/// Client session on server
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
  }

  /// Session ID
  final String id;

  /// The transport for the communication with the client
  final TransportConnection _connection;

  /// The server registry
  final CRDTServerRegistry _serverRegistry;

  /// Session event controller
  final StreamController<SessionEvent> _sessionEventController;

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
    }
  }

  /// Close the session
  Future<void> close() async {
    await tryCatchIgnore(_connection.close);
  }

  /// Handle incoming data from the transport
  void _handleData(List<int> data) {
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
    _sessionEventController.add(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.error,
        message: 'Connection error: $error',
      ),
    );
  }

  /// Handle connection closed
  void _handleConnectionClosed() {
    _sessionEventController.add(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.disconnected,
        message: 'Client disconnected',
      ),
    );
  }

  /// Handle incoming message
  Future<void> _handleMessage(Message message) async {
    switch (message.type) {
      case MessageType.handshakeRequest:
        return _handleHandshakeRequest(message as HandshakeRequestMessage);

      case MessageType.change:
        return _handleChangeMessage(message as ChangeMessage);

      case MessageType.snapshotRequest:
        return _handleSnapshotRequest(message as SnapshotRequestMessage);

      case MessageType.ping:
        return _handlePingMessage(message as PingMessage);

      case MessageType.handshakeResponse:
      case MessageType.error:
      case MessageType.pong:
      case MessageType.snapshot:
        break;
    }
  }

  /// Handle handshake
  Future<void> _handleHandshakeRequest(HandshakeRequestMessage message) async {
    final documentId = message.documentId;

    if (!_serverRegistry.hasDocument(documentId)) {
      // send error message if the document does not exist
      return sendMessage(
        Message.error(
          Protocol.errorDocumentNotFound,
          'Document not found: $documentId',
          documentId,
        ),
      );
    }

    _clientAuthor = message.author;
    _subscribedDocuments.add(documentId);

    final document = _serverRegistry.getDocument(documentId)!;
    final snapshot = _serverRegistry.getLatestSnapshot(documentId);

    final changes = document.exportChanges(from: message.version);

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
      return;
    }

    if (!_subscribedDocuments.contains(documentId)) {
      return;
    }

    try {
      final applied = _serverRegistry.applyChange(documentId, message.change);

      if (applied) {
        _sessionEventController.add(
          SessionEventChangeReceived(
            sessionId: id,
            message: 'Change received and applied for document $documentId',
            documentId: documentId,
            change: message.change,
          ),
        );
      }
    } catch (e) {
      _sessionEventController.add(
        SessionEventGeneric(
          sessionId: id,
          type: SessionEventType.error,
          message: 'Failed to apply change: $e',
        ),
      );
    }
  }

  /// Handle snapshot request
  Future<void> _handleSnapshotRequest(SnapshotRequestMessage message) async {
    final documentId = message.documentId;

    if (!_serverRegistry.hasDocument(documentId)) {
      // send error message if the document does not exist
      return sendMessage(
        Message.error(
          Protocol.errorDocumentNotFound,
          'Document not found: $documentId',
          documentId,
        ),
      );
    }

    if (!_subscribedDocuments.contains(documentId)) {
      _subscribedDocuments.add(documentId);
    }

    final snapshot = _serverRegistry.createSnapshot(documentId);

    final response = Message.snapshot(documentId, snapshot);
    await sendMessage(response);
  }

  Future<void> _handlePingMessage(PingMessage message) async {
    final pongMessage = Message.pong(
      message.documentId,
      message.timestamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    await sendMessage(pongMessage);
  }

  /// Check if the client is subscribed to [documentId]
  bool isSubscribedTo(String documentId) {
    return _subscribedDocuments.contains(documentId);
  }

  /// Dispose the session
  void dispose() {
    _sessionEventController.close();
  }
}
