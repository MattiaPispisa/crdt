import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';

/// Session event types of the CRDT-aware sync protocol (server-client mode).
enum SyncSessionEventType implements SessionEventTypeValue {
  /// Handshake completed
  handshakeCompleted,

  /// Document status created
  documentStatusCreated,

  /// Change applied
  changeApplied,

  /// Client is out of sync
  clientOutOfSync,
}

/// Base class for the server-client (CRDT-aware) session events.
abstract class SyncSessionEvent extends SessionEvent {
  /// Constructor
  const SyncSessionEvent({
    required super.sessionId,
    required super.message,
    required SyncSessionEventType super.type,
  });

  @override
  SyncSessionEventType get type => super.type as SyncSessionEventType;
}

/// Session event for a change applied to the server document.
class SessionEventChangeApplied extends SyncSessionEvent {
  /// Constructor
  const SessionEventChangeApplied({
    required super.sessionId,
    required super.message,
    required this.change,
    required this.documentId,
  }) : super(type: SyncSessionEventType.changeApplied);

  /// The change that was received
  final Change change;

  /// The document id
  final String documentId;
}

/// Session event for a generic sync event (handshake completed, document
/// status created, client out of sync).
class SyncSessionEventGeneric extends SyncSessionEvent {
  /// Constructor
  const SyncSessionEventGeneric({
    required super.sessionId,
    required super.message,
    required super.type,
    this.data,
  });

  /// The data associated with the event
  final Map<String, dynamic>? data;
}
