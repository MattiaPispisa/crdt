import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';

/// Relay message types (range `20-39`).
enum RelayMessageType implements MessageTypeValue {
  /// Join request sent from client to relay after connecting.
  ///
  /// The relay replies with a [RelayMessageType.relayWelcome].
  relayHello(20),

  /// Join response sent from relay to client.
  ///
  /// Carries the persisted room state (snapshot and change log) and the
  /// session id assigned to the client.
  relayWelcome(21),

  /// Change blobs pushed from client to relay.
  ///
  /// The relay persists each blob (one sequence number per blob),
  /// acknowledges with a [RelayMessageType.relayAck] and rebroadcasts the
  /// blobs to the other clients in the room as a
  /// [RelayMessageType.relayChanges].
  relayPush(22),

  /// Acknowledgement of a [RelayMessageType.relayPush], relay to client.
  relayAck(23),

  /// Change blobs rebroadcast from relay to the other clients in the room.
  relayChanges(24),

  /// Snapshot uploaded from client to relay to compact the room log.
  relaySnapshotUpload(25),

  /// Request the current room state, client to relay.
  ///
  /// The relay replies with a [RelayMessageType.relayWelcome] carrying the
  /// current persisted state. Used to re-sync an already joined client.
  relayStateRequest(26);

  const RelayMessageType(this.value);

  @override
  final int value;
}

/// Base class for relay messages.
///
/// The relay never interprets CRDT data: change and snapshot payloads are
/// carried as opaque base64 strings. Only relay clients encode and decode
/// them (as `Change`/`Snapshot` binary formats from `crdt_lf`).
///
/// [Message.documentId] identifies the relay room.
abstract class RelayMessage extends Message {
  /// Constructor
  const RelayMessage(super.type, super.documentId);

  /// Decodes a relay message from [json].
  ///
  /// Returns `null` for type codes outside the relay range, so it can be
  /// chained with other decoders (like [Message.fromJson]).
  static Message? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as int;
    if (type < RelayMessageType.relayHello.value ||
        type > RelayMessageType.relayStateRequest.value) {
      return null;
    }

    switch (RelayMessageType.values[type - RelayMessageType.relayHello.value]) {
      case RelayMessageType.relayHello:
        return RelayHelloMessage.fromJson(json);
      case RelayMessageType.relayWelcome:
        return RelayWelcomeMessage.fromJson(json);
      case RelayMessageType.relayPush:
        return RelayPushMessage.fromJson(json);
      case RelayMessageType.relayAck:
        return RelayAckMessage.fromJson(json);
      case RelayMessageType.relayChanges:
        return RelayChangesMessage.fromJson(json);
      case RelayMessageType.relaySnapshotUpload:
        return RelaySnapshotUploadMessage.fromJson(json);
      case RelayMessageType.relayStateRequest:
        return RelayStateRequestMessage.fromJson(json);
    }
  }
}

/// Join request sent from client to relay after connecting.
class RelayHelloMessage extends RelayMessage {
  /// Constructor
  const RelayHelloMessage({
    required String documentId,
    required this.author,
  }) : super(RelayMessageType.relayHello, documentId);

  /// Create a hello message from a JSON map
  factory RelayHelloMessage.fromJson(Map<String, dynamic> json) {
    return RelayHelloMessage(
      documentId: json['documentId'] as String,
      author: PeerId.parse(json['author'] as String),
    );
  }

  /// The author of the joining client
  final PeerId author;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'author': author.toString(),
    };
  }

  @override
  String toString() {
    return 'RelayHelloMessage(documentId: $documentId, author: $author)';
  }
}

/// Join response sent from relay to client.
class RelayWelcomeMessage extends RelayMessage {
  /// Constructor
  const RelayWelcomeMessage({
    required String documentId,
    required this.sessionId,
    required this.changes,
    required this.seq,
    required this.logLength,
    required this.compact,
    this.snapshot,
  }) : super(RelayMessageType.relayWelcome, documentId);

  /// Create a welcome message from a JSON map
  factory RelayWelcomeMessage.fromJson(Map<String, dynamic> json) {
    return RelayWelcomeMessage(
      documentId: json['documentId'] as String,
      sessionId: json['sessionId'] as String,
      snapshot: json['snapshot'] as String?,
      changes: (json['changes'] as List<dynamic>).cast<String>(),
      seq: json['seq'] as int,
      logLength: json['logLength'] as int,
      compact: json['compact'] as bool,
    );
  }

  /// The session id assigned to the client by the relay
  final String sessionId;

  /// The latest room snapshot (opaque base64), if any
  final String? snapshot;

  /// The room change log after [snapshot] (opaque base64 blobs)
  final List<String> changes;

  /// The last sequence number assigned by the relay for this room
  final int seq;

  /// The current room log length
  final int logLength;

  /// Whether the relay asks this client to upload a snapshot
  /// (see [RelaySnapshotUploadMessage])
  final bool compact;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'sessionId': sessionId,
      'snapshot': snapshot,
      'changes': changes,
      'seq': seq,
      'logLength': logLength,
      'compact': compact,
    };
  }

  @override
  String toString() {
    return 'RelayWelcomeMessage(documentId: $documentId, '
        'sessionId: $sessionId, snapshot: ${snapshot != null}, '
        'changes: ${changes.length}, seq: $seq, '
        'logLength: $logLength, compact: $compact)';
  }
}

/// Change blobs pushed from client to relay.
class RelayPushMessage extends RelayMessage {
  /// Constructor
  const RelayPushMessage({
    required String documentId,
    required this.changes,
  }) : super(RelayMessageType.relayPush, documentId);

  /// Create a push message from a JSON map
  factory RelayPushMessage.fromJson(Map<String, dynamic> json) {
    return RelayPushMessage(
      documentId: json['documentId'] as String,
      changes: (json['changes'] as List<dynamic>).cast<String>(),
    );
  }

  /// The pushed change blobs (opaque base64), one per CRDT change
  final List<String> changes;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'changes': changes,
    };
  }

  @override
  String toString() {
    return 'RelayPushMessage(documentId: $documentId, '
        'changes: ${changes.length})';
  }
}

/// Acknowledgement of a [RelayPushMessage], relay to client.
class RelayAckMessage extends RelayMessage {
  /// Constructor
  const RelayAckMessage({
    required String documentId,
    required this.seq,
    required this.count,
    required this.logLength,
    required this.compact,
  }) : super(RelayMessageType.relayAck, documentId);

  /// Create an ack message from a JSON map
  factory RelayAckMessage.fromJson(Map<String, dynamic> json) {
    return RelayAckMessage(
      documentId: json['documentId'] as String,
      seq: json['seq'] as int,
      count: json['count'] as int,
      logLength: json['logLength'] as int,
      compact: json['compact'] as bool,
    );
  }

  /// The last sequence number assigned to the acknowledged blobs
  final int seq;

  /// How many blobs were persisted by this ack
  final int count;

  /// The current room log length
  final int logLength;

  /// Whether the relay asks this client to upload a snapshot
  /// (see [RelaySnapshotUploadMessage])
  final bool compact;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'seq': seq,
      'count': count,
      'logLength': logLength,
      'compact': compact,
    };
  }

  @override
  String toString() {
    return 'RelayAckMessage(documentId: $documentId, seq: $seq, '
        'count: $count, logLength: $logLength, compact: $compact)';
  }
}

/// Change blobs rebroadcast from relay to the other clients in the room.
class RelayChangesMessage extends RelayMessage {
  /// Constructor
  const RelayChangesMessage({
    required String documentId,
    required this.changes,
    required this.seq,
    this.from,
  }) : super(RelayMessageType.relayChanges, documentId);

  /// Create a changes message from a JSON map
  factory RelayChangesMessage.fromJson(Map<String, dynamic> json) {
    return RelayChangesMessage(
      documentId: json['documentId'] as String,
      changes: (json['changes'] as List<dynamic>).cast<String>(),
      seq: json['seq'] as int,
      from: json['from'] as String?,
    );
  }

  /// The rebroadcast change blobs (opaque base64), one per CRDT change
  final List<String> changes;

  /// The last sequence number assigned to the rebroadcast blobs.
  ///
  /// The blobs cover the sequence range `(seq - changes.length, seq]`.
  /// Clients use it to know which portion of the room log they hold, so a
  /// requested snapshot upload never covers log entries the client has not
  /// imported yet.
  final int seq;

  /// The session id of the client that pushed the changes, if known
  final String? from;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'changes': changes,
      'seq': seq,
      'from': from,
    };
  }

  @override
  String toString() {
    return 'RelayChangesMessage(documentId: $documentId, '
        'changes: ${changes.length}, seq: $seq, from: $from)';
  }
}

/// Snapshot uploaded from client to relay to compact the room log.
class RelaySnapshotUploadMessage extends RelayMessage {
  /// Constructor
  const RelaySnapshotUploadMessage({
    required String documentId,
    required this.snapshot,
    required this.upToSeq,
  }) : super(RelayMessageType.relaySnapshotUpload, documentId);

  /// Create a snapshot upload message from a JSON map
  factory RelaySnapshotUploadMessage.fromJson(Map<String, dynamic> json) {
    return RelaySnapshotUploadMessage(
      documentId: json['documentId'] as String,
      snapshot: json['snapshot'] as String,
      upToSeq: json['upToSeq'] as int,
    );
  }

  /// The uploaded snapshot (opaque base64)
  final String snapshot;

  /// The log sequence number covered by [snapshot]: the relay deletes the
  /// log entries with a sequence number less than or equal to it
  final int upToSeq;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'snapshot': snapshot,
      'upToSeq': upToSeq,
    };
  }

  @override
  String toString() {
    return 'RelaySnapshotUploadMessage(documentId: $documentId, '
        'upToSeq: $upToSeq)';
  }
}

/// Request the current room state, client to relay.
class RelayStateRequestMessage extends RelayMessage {
  /// Constructor
  const RelayStateRequestMessage({
    required String documentId,
  }) : super(RelayMessageType.relayStateRequest, documentId);

  /// Create a state request message from a JSON map
  factory RelayStateRequestMessage.fromJson(Map<String, dynamic> json) {
    return RelayStateRequestMessage(
      documentId: json['documentId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
    };
  }

  @override
  String toString() {
    return 'RelayStateRequestMessage(documentId: $documentId)';
  }
}
