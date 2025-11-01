import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';

/// base message type class
abstract class MessageTypeValue {
  /// index
  int get value;
}

/// Available message types
enum MessageType implements MessageTypeValue {
  /// Handshake request message sent from client to server
  handshakeRequest(0),

  /// Handshake response message sent from server to client
  handshakeResponse(1),

  /// Message containing a CRDT change
  change(2),

  /// Message containing a full snapshot
  documentStatus(3),

  /// Document status request message sent from client to server
  documentStatusRequest(4),

  /// Ping message to check the connection
  ping(5),

  /// Pong message
  pong(6),

  /// Error message
  error(7),

  /// Message containing a set of changes
  changes(8);

  const MessageType(this.value);

  @override
  final int value;
}

/// Base class for all messages exchanged between server and client.
abstract class Message {
  /// Constructor
  const Message(
    this.type,
    this.documentId,
  );

  /// Create a change message
  factory Message.change({
    required String documentId,
    required Change change,
  }) {
    return ChangeMessage(
      documentId: documentId,
      change: change,
    );
  }

  /// Create a changes message
  factory Message.changes({
    required String documentId,
    required List<Change> changes,
  }) {
    return ChangesMessage(documentId: documentId, changes: changes);
  }

  /// Create a document status message
  factory Message.documentStatus({
    required String documentId,
    required Snapshot? snapshot,
    required List<Change>? changes,
  }) {
    return DocumentStatusMessage(
      documentId: documentId,
      snapshot: snapshot,
      changes: changes,
    );
  }

  /// Create a document status request message
  factory Message.documentStatusRequest({
    required String documentId,
    required VersionVector? versionVector,
  }) {
    return DocumentStatusRequestMessage(
      documentId: documentId,
      versionVector: versionVector,
    );
  }

  /// Create a ping message
  factory Message.ping({
    required String documentId,
    required int timestamp,
  }) {
    return PingMessage(
      documentId: documentId,
      timestamp: timestamp,
    );
  }

  /// Create a pong message
  factory Message.pong({
    required String documentId,
    required int originalTimestamp,
    required int responseTimestamp,
  }) {
    return PongMessage(
      documentId: documentId,
      originalTimestamp: originalTimestamp,
      responseTimestamp: responseTimestamp,
    );
  }

  /// Create an error message
  factory Message.error({
    required String documentId,
    required String code,
    required String message,
  }) {
    return ErrorMessage(
      documentId: documentId,
      code: code,
      message: message,
    );
  }

  /// The message type
  final MessageTypeValue type;

  /// The document ID to which the message refers
  final String documentId;

  /// Convert the message to a JSON map
  Map<String, dynamic> toJson();

  /// Serialize the message to a JSON string
  String serialize() {
    return jsonEncode(toJson());
  }

  /// Deserialize a message from a JSON string
  static Message? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as int;
    if (type < 0 || type >= MessageType.values.length) {
      return null;
    }

    switch (MessageType.values[type]) {
      case MessageType.handshakeRequest:
        return HandshakeRequestMessage.fromJson(json);
      case MessageType.handshakeResponse:
        return HandshakeResponseMessage.fromJson(json);
      case MessageType.change:
        return ChangeMessage.fromJson(json);
      case MessageType.changes:
        return ChangesMessage.fromJson(json);
      case MessageType.documentStatus:
        return DocumentStatusMessage.fromJson(json);
      case MessageType.documentStatusRequest:
        return DocumentStatusRequestMessage.fromJson(json);
      case MessageType.ping:
        return PingMessage.fromJson(json);
      case MessageType.pong:
        return PongMessage.fromJson(json);
      case MessageType.error:
        return ErrorMessage.fromJson(json);
    }
  }

  @override
  String toString() {
    return 'Message(type: $type, documentId: $documentId)';
  }
}

/// Handshake request message sent from client to server.
class HandshakeRequestMessage extends Message {
  /// Constructor
  const HandshakeRequestMessage({
    required this.versionVector,
    required String documentId,
    required this.author,
  }) : super(MessageType.handshakeRequest, documentId);

  /// Create a handshake message from a JSON map
  factory HandshakeRequestMessage.fromJson(Map<String, dynamic> json) {
    return HandshakeRequestMessage(
      versionVector: VersionVector.fromJson(
        json['versionVector'] as Map<String, dynamic>,
      ),
      documentId: json['documentId'] as String,
      author: PeerId.parse(json['author'] as String),
    );
  }

  /// The client version vector
  final VersionVector versionVector;

  /// The author of the message
  final PeerId author;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'author': author.toString(),
      'versionVector': versionVector.toJson(),
    };
  }

  @override
  String toString() {
    return 'HandshakeRequestMessage(versionVector: $versionVector, '
        'documentId: $documentId, author: $author)';
  }
}

/// Handshake response message sent from server to client.
class HandshakeResponseMessage extends Message {
  /// Constructor
  const HandshakeResponseMessage({
    required String documentId,
    required this.sessionId,
    this.snapshot,
    this.changes,
  }) : super(MessageType.handshakeResponse, documentId);

  /// Create a handshake response message from a JSON map
  factory HandshakeResponseMessage.fromJson(Map<String, dynamic> json) {
    return HandshakeResponseMessage(
      documentId: json['documentId'] as String,
      snapshot: json['snapshot'] != null
          ? Snapshot.fromJson(json['snapshot'] as Map<String, dynamic>)
          : null,
      changes: json['changes'] != null
          ? (json['changes'] as List<dynamic>)
              .map((c) => Change.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
      sessionId: json['sessionId'] as String,
    );
  }

  /// The snapshot, if present
  final Snapshot? snapshot;

  /// The missing changes, if present
  final List<Change>? changes;

  /// The session ID to which the message refers
  final String sessionId;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'snapshot': snapshot?.toJson(),
      'changes': changes?.map((c) => c.toJson()).toList(),
      'sessionId': sessionId,
    };
  }

  @override
  String toString() {
    return 'HandshakeResponseMessage(snapshot: $snapshot, '
        'changes: $changes, sessionId: $sessionId)';
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
      'type': type.value,
      'documentId': documentId,
      'change': change.toJson(),
    };
  }

  @override
  String toString() {
    return 'ChangeMessage(change: $change, documentId: $documentId)';
  }
}

/// Message containing a set of changes.
class ChangesMessage extends Message {
  /// Constructor
  const ChangesMessage({
    required this.changes,
    required String documentId,
  }) : super(MessageType.changes, documentId);

  /// Create a changes message from a JSON map
  factory ChangesMessage.fromJson(Map<String, dynamic> json) {
    return ChangesMessage(
      changes: (json['changes'] as List<dynamic>)
          .map((c) => Change.fromJson(c as Map<String, dynamic>))
          .toList(),
      documentId: json['documentId'] as String,
    );
  }

  /// The CRDT [Change]s
  final List<Change> changes;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'changes': changes.map((c) => c.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'ChangesMessage(changes: $changes, documentId: $documentId)';
  }
}

/// Message containing a full snapshot.
class DocumentStatusMessage extends Message {
  /// Constructor
  const DocumentStatusMessage({
    required String documentId,
    this.snapshot,
    this.changes,
  }) : super(MessageType.documentStatus, documentId);

  /// Create a snapshot message from a JSON map
  factory DocumentStatusMessage.fromJson(Map<String, dynamic> json) {
    return DocumentStatusMessage(
      snapshot: Snapshot.fromJson(json['snapshot'] as Map<String, dynamic>),
      documentId: json['documentId'] as String,
    );
  }

  /// The CRDT snapshot
  final Snapshot? snapshot;

  /// The CRDT changes
  final List<Change>? changes;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'snapshot': snapshot?.toJson(),
      'changes': changes?.map((c) => c.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'SnapshotMessage(snapshot: $snapshot, documentId: $documentId)';
  }
}

/// Snapshot request message sent from client to server.
class DocumentStatusRequestMessage extends Message {
  /// Constructor
  const DocumentStatusRequestMessage({
    required String documentId,
    this.versionVector,
  }) : super(MessageType.documentStatusRequest, documentId);

  /// Create a snapshot request message from a JSON map
  factory DocumentStatusRequestMessage.fromJson(Map<String, dynamic> json) {
    return DocumentStatusRequestMessage(
      versionVector: json['versionVector'] != null
          ? VersionVector.fromJson(
              json['versionVector'] as Map<String, dynamic>,
            )
          : null,
      documentId: json['documentId'] as String,
    );
  }

  /// The client version vector
  final VersionVector? versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'versionVector': versionVector?.toJson(),
    };
  }

  @override
  String toString() {
    return 'DocumentStatusRequestMessage(versionVector: $versionVector, '
        'documentId: $documentId)';
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
      'type': type.value,
      'documentId': documentId,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'PingMessage(timestamp: $timestamp, documentId: $documentId)';
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
      'type': type.value,
      'documentId': documentId,
      'originalTimestamp': originalTimestamp,
      'responseTimestamp': responseTimestamp,
    };
  }

  @override
  String toString() {
    return 'PongMessage(originalTimestamp: $originalTimestamp, '
        'responseTimestamp: $responseTimestamp, documentId: $documentId)';
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
      'type': type.value,
      'documentId': documentId,
      'code': code,
      'message': message,
    };
  }

  @override
  String toString() {
    return 'ErrorMessage(code: $code, '
        'message: $message, documentId: $documentId)';
  }
}
