import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';

/// Session event types of the relay protocol.
enum RelaySessionEventType implements SessionEventTypeValue {
  /// A client joined a relay room
  relayJoined,

  /// A client pushed change blobs to a relay room
  relayChangesPushed,

  /// A client uploaded a snapshot to compact a relay room log
  relaySnapshotUploaded,
}

/// Base class for the relay session events.
abstract class RelaySessionEvent extends SessionEvent {
  /// Constructor
  const RelaySessionEvent({
    required super.sessionId,
    required super.message,
    required RelaySessionEventType super.type,
  });

  @override
  RelaySessionEventType get type => super.type as RelaySessionEventType;
}

/// Session event for a client that joined a relay room.
class RelaySessionEventJoined extends RelaySessionEvent {
  /// Constructor
  const RelaySessionEventJoined({
    required super.sessionId,
    required super.message,
    required this.documentId,
    required this.author,
  }) : super(type: RelaySessionEventType.relayJoined);

  /// The room id
  final String documentId;

  /// The author of the joining client
  final PeerId author;
}

/// Session event for change blobs pushed to a relay room.
///
/// The relay server broadcasts the blobs to the other clients in the room
/// when this event is emitted.
class RelaySessionEventChangesPushed extends RelaySessionEvent {
  /// Constructor
  const RelaySessionEventChangesPushed({
    required super.sessionId,
    required super.message,
    required this.documentId,
    required this.changes,
    required this.seq,
  }) : super(type: RelaySessionEventType.relayChangesPushed);

  /// The room id
  final String documentId;

  /// The pushed change blobs (opaque base64)
  final List<String> changes;

  /// The last sequence number assigned to the pushed blobs
  final int seq;
}

/// Session event for a snapshot uploaded to compact a relay room log.
class RelaySessionEventSnapshotUploaded extends RelaySessionEvent {
  /// Constructor
  const RelaySessionEventSnapshotUploaded({
    required super.sessionId,
    required super.message,
    required this.documentId,
    required this.upToSeq,
  }) : super(type: RelaySessionEventType.relaySnapshotUploaded);

  /// The room id
  final String documentId;

  /// The last log sequence number covered by the uploaded snapshot
  final int upToSeq;
}
