import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';

/// Available message types
enum MessageType {
  /// Handshake request message sent from client to server
  handshakeRequest,

  /// Handshake response message sent from server to client
  handshakeResponse,

  /// Message containing a CRDT change
  change,

  /// Message containing a full snapshot
  snapshot,

  /// Snapshot request message sent from client to server
  snapshotRequest,

  /// Ping message to check the connection
  ping,

  /// Pong message
  pong,

  /// Error message
  error,
}

/// Base class for all messages exchanged between server and client.
abstract class Message {
  /// Constructor
  const Message(this.type, this.documentId);

  /// The message type
  final MessageType type;

  /// The document ID to which the message refers
  final String documentId;

  /// Convert the message to a JSON map
  Map<String, dynamic> toJson();

  /// Serialize the message to a JSON string
  String serialize() {
    return jsonEncode(toJson());
  }

  /// Deserialize a message from a JSON string
  static Message fromJson(Map<String, dynamic> json) {
    final type = MessageType.values[json['type'] as int];

    switch (type) {
      case MessageType.handshakeRequest:
        return HandshakeRequestMessage.fromJson(json);
      case MessageType.handshakeResponse:
        return HandshakeResponseMessage.fromJson(json);
      case MessageType.change:
        return ChangeMessage.fromJson(json);
      case MessageType.snapshot:
        return SnapshotMessage.fromJson(json);
      case MessageType.snapshotRequest:
        return SnapshotRequestMessage.fromJson(json);
      case MessageType.ping:
        return PingMessage.fromJson(json);
      case MessageType.pong:
        return PongMessage.fromJson(json);
      case MessageType.error:
        return ErrorMessage.fromJson(json);
    }
  }
}

/// Handshake request message sent from client to server.
class HandshakeRequestMessage extends Message {
  /// Constructor
  const HandshakeRequestMessage({
    required this.peerId,
    required this.versionVector,
    required String documentId,
  }) : super(MessageType.handshakeRequest, documentId);

  /// Create a handshake message from a JSON map
  factory HandshakeRequestMessage.fromJson(Map<String, dynamic> json) {
    return HandshakeRequestMessage(
      peerId: PeerId.parse(json['peerId'] as String),
      versionVector:
          VersionVector.fromJson(json['versionVector'] as Map<String, dynamic>),
      documentId: json['documentId'] as String,
    );
  }

  /// The client peer ID
  final PeerId peerId;

  // TODO(mattia): version vector or dag operationIds ?
  /// The client version vector
  final VersionVector versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'peerId': peerId.toString(),
      'versionVector': versionVector.toJson(),
    };
  }
}

/// Handshake response message sent from server to client.
class HandshakeResponseMessage extends Message {
  /// Constructor
  const HandshakeResponseMessage({
    required this.needsFullUpdate,
    required String documentId,
    this.snapshot,
    this.changes,
  }) : super(MessageType.handshakeResponse, documentId);

  /// Create a handshake response message from a JSON map
  factory HandshakeResponseMessage.fromJson(Map<String, dynamic> json) {
    return HandshakeResponseMessage(
      needsFullUpdate: json['needsFullUpdate'] as bool,
      documentId: json['documentId'] as String,
      snapshot: json['snapshot'] != null
          ? Snapshot.fromJson(json['snapshot'] as Map<String, dynamic>)
          : null,
      changes: json['changes'] != null
          ? (json['changes'] as List)
              .map((c) => Change.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Indicates if a full update is needed
  final bool needsFullUpdate;

  /// The snapshot, if present
  final Snapshot? snapshot;

  /// The missing changes, if present
  final List<Change>? changes;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'needsFullUpdate': needsFullUpdate,
      'snapshot': snapshot?.toJson(),
      'changes': changes?.map((c) => c.toJson()).toList(),
    };
  }
}

/// Message containing a CRDT change.
class ChangeMessage extends Message {
  /// Constructor
  const ChangeMessage({
    required this.change,
    required String documentId,
  }) : super(MessageType.change, documentId);

  /// Create a change message from a JSON map
  factory ChangeMessage.fromJson(Map<String, dynamic> json) {
    return ChangeMessage(
      change: Change.fromJson(json['change'] as Map<String, dynamic>),
      documentId: json['documentId'] as String,
    );
  }

  /// The CRDT change
  final Change change;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'change': change.toJson(),
    };
  }
}

/// Message containing a full snapshot.
class SnapshotMessage extends Message {
  /// Constructor
  const SnapshotMessage({
    required this.snapshot,
    required String documentId,
  }) : super(MessageType.snapshot, documentId);

  /// Create a snapshot message from a JSON map
  factory SnapshotMessage.fromJson(Map<String, dynamic> json) {
    return SnapshotMessage(
      snapshot: Snapshot.fromJson(json['snapshot'] as Map<String, dynamic>),
      documentId: json['documentId'] as String,
    );
  }

  /// The CRDT snapshot
  final Snapshot snapshot;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'snapshot': snapshot.toJson(),
    };
  }
}

/// Snapshot request message sent from client to server.
class SnapshotRequestMessage extends Message {
  /// Constructor
  const SnapshotRequestMessage({
    required this.peerId,
    required this.versionVector,
    required String documentId,
  }) : super(MessageType.snapshotRequest, documentId);

  /// Create a snapshot request message from a JSON map
  factory SnapshotRequestMessage.fromJson(Map<String, dynamic> json) {
    return SnapshotRequestMessage(
      peerId: PeerId.parse(json['peerId'] as String),
      versionVector:
          VersionVector.fromJson(json['versionVector'] as Map<String, dynamic>),
      documentId: json['documentId'] as String,
    );
  }

  /// The client peer ID
  final PeerId peerId;

  /// The client version vector
  final VersionVector versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'peerId': peerId.toString(),
      'versionVector': versionVector.toJson(),
    };
  }
}

/// Ping message to check the connection.
class PingMessage extends Message {
  /// Constructor
  const PingMessage({
    required this.timestamp,
    required String documentId,
  }) : super(MessageType.ping, documentId);

  /// Create a ping message from a JSON map
  factory PingMessage.fromJson(Map<String, dynamic> json) {
    return PingMessage(
      timestamp: json['timestamp'] as int,
      documentId: json['documentId'] as String,
    );
  }

  /// Timestamp of the ping
  final int timestamp;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'timestamp': timestamp,
    };
  }
}

/// Pong message.
class PongMessage extends Message {
  /// Constructor
  const PongMessage({
    required this.originalTimestamp,
    required this.responseTimestamp,
    required String documentId,
  }) : super(MessageType.pong, documentId);

  /// Create a pong message from a JSON map
  factory PongMessage.fromJson(Map<String, dynamic> json) {
    return PongMessage(
      originalTimestamp: json['originalTimestamp'] as int,
      responseTimestamp: json['responseTimestamp'] as int,
      documentId: json['documentId'] as String,
    );
  }

  /// Original ping timestamp
  final int originalTimestamp;

  /// Response timestamp
  final int responseTimestamp;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'originalTimestamp': originalTimestamp,
      'responseTimestamp': responseTimestamp,
    };
  }
}

/// Error message.
class ErrorMessage extends Message {
  /// Constructor
  const ErrorMessage({
    required this.code,
    required this.message,
    required String documentId,
  }) : super(MessageType.error, documentId);

  /// Create an error message from a JSON map
  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    return ErrorMessage(
      code: json['code'] as String,
      message: json['message'] as String,
      documentId: json['documentId'] as String,
    );
  }

  /// Error code
  final String code;

  /// Error message
  final String message;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'documentId': documentId,
      'code': code,
      'message': message,
    };
  }
}
