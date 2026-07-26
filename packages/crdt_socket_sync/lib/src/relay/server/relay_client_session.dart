import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:crdt_socket_sync/src/relay/server/compaction.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_session_event.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';

/// {@template relay_client_session}
/// Relay client session on server.
///
/// Implements the relay protocol on top of [ClientSession]: the session
/// persists pushed change blobs in the [RelayStore] and serves the room
/// state on join, without ever interpreting CRDT data.
/// {@endtemplate}
class RelayClientSession extends ClientSession {
  /// {@macro relay_client_session}
  ///
  /// Constructor
  RelayClientSession({
    required super.id,
    required super.connection,
    required RelayStore store,
    required RelayCompactionCoordinator compaction,
    super.compressor,
    MessageCodec<Message>? messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _store = store,
        _compaction = compaction,
        super.base(
          messageCodec: messageCodec ??
              JsonMessageCodec<Message>(
                toJson: (message) => message.toJson(),
                fromJson: (json) =>
                    RelayMessage.fromJson(json) ?? Message.fromJson(json),
              ),
        );

  /// The relay store
  final RelayStore _store;

  /// The compaction coordinator, shared across the server sessions
  final RelayCompactionCoordinator _compaction;

  /// Client peer ID, from the hello message
  PeerId? _clientAuthor;

  /// The client peer ID, if the client already joined a room.
  PeerId? get clientAuthor => _clientAuthor;

  @override
  Future<void> handleTypedMessage(Message message) async {
    if (message is RelayHelloMessage) {
      return _handleHello(message);
    }
    if (message is RelayPushMessage) {
      return _handlePush(message);
    }
    if (message is RelaySnapshotUploadMessage) {
      return _handleSnapshotUpload(message);
    }
    if (message is RelayStateRequestMessage) {
      return _handleStateRequest(message);
    }
    if (message is PingMessage) {
      return _handlePingMessage(message);
    }
  }

  @override
  void handleUndecodable(List<int> data) {
    final type = Message.getTypeOrNull(data);

    // Core-protocol frames (below the relay range) reaching a relay server are
    // almost always a CRDT-aware sync client connected to the wrong server.
    // The relay does not decode them (they carry no relay semantics), so they
    // surface here as undecodable — answer with a diagnostic instead of a
    // silent drop. Ping/pong/error decode fine and never reach this path.
    if (type != null && type < RelayMessageType.relayHello.value) {
      unawaited(
        sendMessage(
          Message.error(
            documentId: _documentIdOf(data) ?? '',
            code: Protocol.errorInvalidMessage,
            message: 'This server runs the relay protocol: '
                'the CRDT-aware sync protocol is not supported. '
                'Connect with a relay client.',
          ),
        ),
      );
      return;
    }

    super.handleUndecodable(data);
  }

  /// Best-effort read of the `documentId` field of an undecodable [data] frame.
  String? _documentIdOf(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data));
      if (json is Map<String, dynamic>) {
        final id = json['documentId'];
        return id is String ? id : null;
      }
    } catch (_) {
      // Not JSON: no documentId to report.
    }
    return null;
  }

  /// Handle a join request
  ///
  /// 1. Register the room subscription (notifying plugins)
  /// 1. Send the persisted room state as a welcome
  Future<void> _handleHello(RelayHelloMessage message) async {
    final documentId = message.documentId;

    _clientAuthor = message.author;
    registerDocument(documentId);

    await _sendRoomState(documentId);

    addSessionEvent(
      RelaySessionEventJoined(
        sessionId: id,
        message: 'Client joined relay room $documentId',
        documentId: documentId,
        author: message.author,
      ),
    );
  }

  /// Handle pushed change blobs
  ///
  /// 1. Persist the blobs (one sequence number per blob)
  /// 1. Acknowledge the push
  /// 1. Emit [RelaySessionEventChangesPushed] so the server rebroadcasts
  ///    the blobs to the other clients in the room
  Future<void> _handlePush(RelayPushMessage message) async {
    final documentId = message.documentId;

    if (!_guardSubscribed(documentId, action: 'push changes')) {
      return;
    }

    if (message.changes.isEmpty) {
      return;
    }

    final seq = await _store.append(documentId, message.changes);
    final logLength = await _store.logLength(documentId);

    await sendMessage(
      RelayAckMessage(
        documentId: documentId,
        seq: seq,
        count: message.changes.length,
        logLength: logLength,
        compact: _compaction.shouldCompact(documentId, logLength),
      ),
    );

    addSessionEvent(
      RelaySessionEventChangesPushed(
        sessionId: id,
        message: '${message.changes.length} change blobs pushed'
            ' to relay room $documentId',
        documentId: documentId,
        changes: message.changes,
        seq: seq,
      ),
    );
  }

  /// Handle a snapshot upload
  ///
  /// 1. Persist the snapshot, truncating the covered log
  /// 1. Clear the compaction rate limit for the room
  Future<void> _handleSnapshotUpload(
    RelaySnapshotUploadMessage message,
  ) async {
    final documentId = message.documentId;

    if (!_guardSubscribed(documentId, action: 'upload a snapshot')) {
      return;
    }

    await _store.saveSnapshot(
      documentId,
      RelaySnapshotRecord(
        blob: message.snapshot,
        upToSeq: message.upToSeq,
      ),
    );
    _compaction.reset(documentId);

    addSessionEvent(
      RelaySessionEventSnapshotUploaded(
        sessionId: id,
        message: 'Snapshot uploaded for relay room $documentId'
            ' (log truncated up to ${message.upToSeq})',
        documentId: documentId,
        upToSeq: message.upToSeq,
      ),
    );
  }

  /// Handle a state request: reply with the current persisted room state.
  Future<void> _handleStateRequest(RelayStateRequestMessage message) async {
    if (!_guardSubscribed(message.documentId, action: 'request the state')) {
      return;
    }

    await _sendRoomState(message.documentId);
  }

  Future<void> _handlePingMessage(PingMessage message) async {
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

  /// Send the persisted state of [documentId] as a [RelayWelcomeMessage].
  Future<void> _sendRoomState(String documentId) async {
    final snapshot = await _store.getSnapshot(documentId);
    final log = await _store.readLog(
      documentId,
      afterSeq: snapshot?.upToSeq ?? 0,
    );
    final seq = await _store.lastSeq(documentId);
    final logLength = await _store.logLength(documentId);

    await sendMessage(
      RelayWelcomeMessage(
        documentId: documentId,
        sessionId: id,
        snapshot: snapshot?.blob,
        changes: log.map((entry) => entry.blob).toList(),
        seq: seq,
        logLength: logLength,
        compact: _compaction.shouldCompact(documentId, logLength),
      ),
    );
  }

  /// Emit an error event (and return `false`) when this session did not
  /// join [documentId].
  bool _guardSubscribed(String documentId, {required String action}) {
    if (isSubscribedTo(documentId)) {
      return true;
    }
    addSessionEvent(
      SessionEventGeneric(
        sessionId: id,
        type: SessionEventType.error,
        message: 'Client did not join relay room $documentId'
            ', cannot $action',
      ),
    );
    return false;
  }
}
