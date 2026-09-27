import 'dart:async';

import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/common/server/event.dart';
import 'package:crdt_socket_sync/src/common/server/session_host.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:crdt_socket_sync/src/relay/server/compaction.dart';
import 'package:crdt_socket_sync/src/relay/server/in_memory_relay_store.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_client_session.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_session_event.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';
import 'package:meta/meta.dart';

/// {@template relay_session_host}
/// Relay session host: the server half of the relay protocol, with no
/// transport of its own.
///
/// A relay rebroadcasts opaque CRDT change blobs to the other clients of a
/// room and persists them in a [RelayStore], without ever interpreting CRDT
/// data: merging is entirely a client concern. One host serves many rooms,
/// keyed by document id.
///
/// Feed it connections with [SessionHostServer.acceptConnection]. For a host
/// that owns its own `dart:io` socket, use `WebSocketRelayServer` instead.
/// {@endtemplate}
class RelaySessionHost extends SessionHostServer<RelayClientSession> {
  /// {@macro relay_session_host}
  ///
  /// A `null` [messageCodec] leaves each [RelayClientSession] to build the
  /// relay codec itself.
  RelaySessionHost({
    RelayStore? store,
    RelayCompactionCoordinator? compaction,
    super.compressor,
    super.messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _store = store ?? InMemoryRelayStore(),
        _compaction = compaction ?? RelayCompactionCoordinator();

  final RelayStore _store;

  final RelayCompactionCoordinator _compaction;

  /// The room persistence used by this host.
  RelayStore get store => _store;

  /// The compaction coordinator, shared across this host's sessions.
  RelayCompactionCoordinator get compaction => _compaction;

  @protected
  @override
  String get debugLabel => 'RelaySessionHost';

  @protected
  @override
  String get startedMessage => 'Relay server started';

  @protected
  @override
  String get stoppedMessage => 'Relay server stopped';

  @protected
  @override
  String startFailureMessage(Object error) =>
      'Failed to start relay server: $error';

  @protected
  @override
  RelayClientSession createSession({
    required String id,
    required TransportConnection connection,
  }) {
    return RelayClientSession(
      id: id,
      connection: connection,
      store: _store,
      compaction: _compaction,
      compressor: compressor,
      plugins: plugins,
      messageCodec: messageCodec,
      maxBufferSize: maxBufferSize,
    );
  }

  @protected
  @override
  FutureOr<void> handleSessionEvent(SessionEvent event) async {
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

    return super.handleSessionEvent(event);
  }

  /// Add a server event for a relay join event
  void _handleSessionEventJoined(RelaySessionEventJoined event) {
    addServerEvent(
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
    addServerEvent(
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
    addServerEvent(
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
}
