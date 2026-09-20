import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/common/server/event.dart';
import 'package:crdt_socket_sync/src/common/server/session_host.dart';
import 'package:crdt_socket_sync/src/server_client/common/common.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_client_session.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';
import 'package:meta/meta.dart';

/// {@template document_session_host}
/// CRDT-aware session host: the server half of the document sync protocol,
/// with no transport of its own.
///
/// It keeps the [CRDTServerRegistry], turns accepted connections into
/// [DocumentClientSession]s, rebroadcasts applied changes, and takes an
/// aligned snapshot once every subscribed client has confirmed the server's
/// state.
///
/// Feed it connections with [SessionHostServer.acceptConnection]. For a host
/// that owns its own `dart:io` socket, use `WebSocketServer` instead.
/// {@endtemplate}
class DocumentSessionHost extends SessionHostServer<DocumentClientSession> {
  /// {@macro document_session_host}
  DocumentSessionHost({
    required CRDTServerRegistry serverRegistry,
    super.compressor,
    super.messageCodec,
    super.maxBufferSize,
    super.plugins,
  }) : _serverRegistry = serverRegistry;

  final CRDTServerRegistry _serverRegistry;

  /// The registry holding the documents this host serves.
  CRDTServerRegistry get serverRegistry => _serverRegistry;

  @protected
  @override
  String get debugLabel => 'DocumentSessionHost';

  @protected
  @override
  DocumentClientSession createSession({
    required String id,
    required TransportConnection connection,
  }) {
    return DocumentClientSession(
      id: id,
      connection: connection,
      serverRegistry: _serverRegistry,
      compressor: compressor,
      plugins: plugins,
      messageCodec: messageCodec,
      maxBufferSize: maxBufferSize,
    );
  }

  @protected
  @override
  Future<void> onDispose() async {
    // The registry closes what it holds open, and a durable one writes what
    // is still waiting first. Walking `documentIds` here instead would read
    // every document on disk back into memory just to dispose it, and would
    // leave the registry holding disposed documents.
    try {
      await _serverRegistry.close();
    } catch (e) {
      addServerEvent(
        ServerEvent(
          type: ServerEventType.error,
          message: 'Error closing the document registry: $e',
        ),
      );
    }
  }

  @protected
  @override
  FutureOr<void> handleSessionEvent(SessionEvent event) async {
    if (event is SyncSessionEvent) {
      switch (event.type) {
        case SyncSessionEventType.handshakeCompleted:
          return _handleSessionEventHandshakeCompleted(
            event as SyncSessionEventGeneric,
          );

        case SyncSessionEventType.changeApplied:
          return _handleSessionEventChangeApplied(
            event as SessionEventChangeApplied,
          );

        case SyncSessionEventType.documentStatusCreated:
          return _handleSessionEventDocumentStatusRequest(
            event as SyncSessionEventGeneric,
          );

        case SyncSessionEventType.clientOutOfSync:
          return _handleSessionEventClientOutOfSync(
            event as SyncSessionEventGeneric,
          );
      }
    }

    return super.handleSessionEvent(event);
  }

  /// Add a server event for a handshake completed event
  Future<void> _handleSessionEventHandshakeCompleted(
    SyncSessionEventGeneric event,
  ) async {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientHandshake,
        message:
            'Session ${event.sessionId} handshake completed: ${event.message}',
        data: event.data,
      ),
    );
    await maybeTakeAlignedSnapshotForSession(event.sessionId);
  }

  /// Run the snapshot coordinator for every document [sessionId] is subscribed
  /// to.
  Future<void> maybeTakeAlignedSnapshotForSession(String sessionId) async {
    final session = sessionById(sessionId);
    if (session == null) {
      return;
    }
    for (final documentId in session.subscribedDocuments) {
      await maybeTakeAlignedSnapshot(documentId);
    }
  }

  /// Take a snapshot (and prune the confirmed history) when every client
  /// subscribed to [documentId] has confirmed at least the server's current
  /// state.
  ///
  /// Alignment is derived from the version vectors clients report on their
  /// pings (and at handshake). The stability frontier is the intersection
  /// (per-peer minimum) of those vectors. Snapshotting only when the frontier
  /// covers the server's current version guarantees pruning never drops
  /// history a client has not yet confirmed — a lagging client still re-syncs
  /// from the stored snapshot on its next handshake.
  Future<void> maybeTakeAlignedSnapshot(String documentId) async {
    if (!isRunning) {
      return;
    }

    final subscribed = sessions.values
        .where((session) => session.isSubscribedTo(documentId))
        .toList();
    if (subscribed.isEmpty) {
      return;
    }

    final versionVectors = <VersionVector>[];
    for (final session in subscribed) {
      final versionVector = session.lastKnownVersionVector;
      if (versionVector == null) {
        // A subscribed client has not reported its state yet: we cannot know
        // how far it has advanced, so pruning would be unsafe.
        return;
      }
      versionVectors.add(versionVector);
    }

    final frontier = VersionVector.intersection(versionVectors);

    final document = await _serverRegistry.getDocument(documentId);
    if (document == null) {
      return;
    }

    final serverVersion = document.getVersionVector();
    if (serverVersion.isEmpty) {
      return;
    }

    // Every client has confirmed at least the server's current state.
    if (!frontier.isStrictlyNewerOrEqualThan(serverVersion)) {
      return;
    }

    // Avoid redundant work: skip if a snapshot already covers this state.
    final existing = await _serverRegistry.getLatestSnapshot(documentId);
    if (existing != null &&
        !serverVersion.isStrictlyNewerThan(existing.versionVector)) {
      return;
    }

    await _serverRegistry.createSnapshot(documentId);

    addServerEvent(
      ServerEvent(
        type: ServerEventType.snapshotCreated,
        message: 'All clients aligned on document $documentId: '
            'snapshot taken and confirmed history pruned',
        data: {
          'documentId': documentId,
        },
      ),
    );
  }

  /// 1. Add a server event for the change applied
  /// 1. Broadcast the change to the other clients
  Future<void> _handleSessionEventChangeApplied(
    SessionEventChangeApplied event,
  ) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientChangeApplied,
        message: 'Session ${event.sessionId} change applied: ${event.message}',
      ),
    );
    return broadcastMessage(
      SyncMessage.change(
        documentId: event.documentId,
        change: event.change,
      ),
      excludeClientIds: [event.sessionId],
    );
  }

  /// Add a server event for a client out of sync event
  void _handleSessionEventClientOutOfSync(SyncSessionEventGeneric event) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientOutOfSync,
        message: 'Session ${event.sessionId} out of sync: ${event.message}',
      ),
    );
  }

  /// Add a server event for a document status request event
  void _handleSessionEventDocumentStatusRequest(
    SyncSessionEventGeneric event,
  ) {
    addServerEvent(
      ServerEvent(
        type: ServerEventType.clientDocumentStatusCreated,
        message: 'Session ${event.sessionId} document'
            ' status request: ${event.message}',
      ),
    );
  }

  @protected
  @override
  Future<void> handleSessionEventPingReceived(
    SessionEventGeneric event,
  ) async {
    super.handleSessionEventPingReceived(event);
    // Clients piggy-back their version vector on pings; a ping may complete a
    // fleet-wide alignment and let the server snapshot + prune.
    await maybeTakeAlignedSnapshotForSession(event.sessionId);
  }
}
