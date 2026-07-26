import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/server_client/common/common.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';

/// {@template document_client_session}
/// CRDT-aware client session on server.
///
/// Implements the document sync protocol on top of [ClientSession]:
/// handshake with version vectors, applying incoming changes to the
/// [CRDTServerRegistry] and answering document status requests.
/// {@endtemplate}
class DocumentClientSession extends ClientSession {
  /// {@macro document_client_session}
  ///
  /// Constructor
  DocumentClientSession({
    required super.id,
    required super.connection,
    required CRDTServerRegistry serverRegistry,
    super.compressor,
    MessageCodec<Message>? messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _serverRegistry = serverRegistry,
        super.base(
          messageCodec: messageCodec ??
              JsonMessageCodec<Message>(
                toJson: (message) => message.toJson(),
                fromJson: (json) =>
                    SyncMessage.fromJson(json) ?? Message.fromJson(json),
              ),
        );

  /// The server registry
  final CRDTServerRegistry _serverRegistry;

  /// Client peer ID
  PeerId? _clientAuthor;

  /// The client's most recently reported version vector.
  ///
  /// Seeded from the handshake and refreshed from every ping that carries one.
  /// The server uses it to know how far this client has advanced so it can
  /// take a snapshot once every client has confirmed the current state.
  VersionVector? _lastKnownVersionVector;

  /// The client's most recently reported version vector, if any.
  VersionVector? get lastKnownVersionVector => _lastKnownVersionVector;

  @override
  Future<void> handleTypedMessage(Message message) async {
    switch (message.type) {
      case MessageType.handshakeRequest:
        return _handleHandshakeRequest(
          message as HandshakeRequestMessage,
        );

      case MessageType.change:
        final changeMessage = message as ChangeMessage;
        return _handleChangesMessage(
          changes: [changeMessage.change],
          documentId: changeMessage.documentId,
        );

      case MessageType.changes:
        final changesMessage = message as ChangesMessage;
        return _handleChangesMessage(
          changes: changesMessage.changes,
          documentId: changesMessage.documentId,
        );

      case MessageType.documentStatusRequest:
        return _handleDocumentStatusRequest(
          message as DocumentStatusRequestMessage,
        );

      case MessageType.ping:
        return _handlePingMessage(message as PingMessage);
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
    _lastKnownVersionVector = message.versionVector;
    registerDocument(documentId);

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

    addSessionEvent(
      SyncSessionEventGeneric(
        sessionId: id,
        type: SyncSessionEventType.handshakeCompleted,
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
      addSessionEvent(
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
      addSessionEvent(
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
          addSessionEvent(
            SessionEventChangeApplied(
              sessionId: id,
              message: 'Change received and applied for document $documentId',
              documentId: documentId,
              change: change,
            ),
          );
        } else {
          addSessionEvent(
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
        addSessionEvent(
          SyncSessionEventGeneric(
            sessionId: id,
            type: SyncSessionEventType.clientOutOfSync,
            message: 'Client is out of sync. Please re-sync.',
          ),
        );
      } catch (e) {
        addSessionEvent(
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
      addSessionEvent(
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
      registerDocument(documentId, notifyPlugins: false);
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

    // Get the server's version vector representing
    // the state after snapshot and changes
    final serverVersionVector = document.getVersionVector();

    final response = SyncMessage.documentStatus(
      documentId: documentId,
      snapshot: snapshot,
      changes: changes,
      versionVector: serverVersionVector,
    );
    await sendMessage(response);

    addSessionEvent(
      SyncSessionEventGeneric(
        sessionId: id,
        type: SyncSessionEventType.documentStatusCreated,
        message: 'Snapshot request completed for document $documentId',
        data: {
          'documentId': documentId,
          'peerId': _clientAuthor.toString(),
        },
      ),
    );
  }

  Future<void> _handlePingMessage(PingMessage message) async {
    if (message.versionVector != null) {
      _lastKnownVersionVector = message.versionVector;
    }

    final pongMessage = Message.pong(
      documentId: message.documentId,
      originalTimestamp: message.timestamp,
      responseTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await sendMessage(pongMessage);

    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.pingReceived,
        message: 'Ping received from client',
      ),
    );
  }
}
