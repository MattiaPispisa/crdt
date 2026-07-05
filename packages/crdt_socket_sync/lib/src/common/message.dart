import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';

/// Base64-encodes the binary representation of [change].
String _encodeChange(Change change) => base64Encode(change.toBytes());

/// Decodes a base64-encoded [Change].
Change _decodeChange(String value) => Change.fromBytes(base64Decode(value));

/// Base64-encodes the binary representation of [vector].
String _encodeVersionVector(VersionVector vector) =>
    base64Encode(vector.toBytes());

/// Decodes a base64-encoded [VersionVector].
VersionVector _decodeVersionVector(String value) =>
    VersionVector.fromBytes(base64Decode(value));

/// Base64-encodes the binary representation of [snapshot].
String _encodeSnapshot(Snapshot snapshot) => base64Encode(snapshot.toBytes());

/// Decodes a base64-encoded [Snapshot].
Snapshot _decodeSnapshot(String value) =>
    Snapshot.fromBytes(base64Decode(value));

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
    required VersionVector versionVector,
  }) {
    return DocumentStatusMessage(
      documentId: documentId,
      snapshot: snapshot,
      changes: changes,
      versionVector: versionVector,
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
    VersionVector? versionVector,
  }) {
    return PingMessage(
      documentId: documentId,
      timestamp: timestamp,
      versionVector: versionVector,
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

  /// Safely reads the raw `type` code of an encoded message [data] frame,
  /// without throwing.
  ///
  /// [data] is expected to be the (uncompressed) UTF-8 JSON payload produced
  /// by the message codec. Returns `null` when the frame is not valid JSON or
  /// carries no integer `type`.
  ///
  /// Unlike [fromJson], the code does not need to match a known [MessageType],
  /// so plugin message codes (e.g. `100+`) are reported too. This makes it
  /// useful to diagnose a frame that cannot be decoded because its plugin has
  /// not been registered on this side of the connection.
  static int? getTypeOrNull(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data));
      if (json is Map<String, dynamic>) {
        final type = json['type'];
        return type is int ? type : null;
      }
    } catch (_) {
      // Not decodable (malformed or compressed): no type to report.
    }
    return null;
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
      versionVector: _decodeVersionVector(json['versionVector'] as String),
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
      'versionVector': _encodeVersionVector(versionVector),
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
    required this.versionVector,
    this.snapshot,
    this.changes,
  }) : super(MessageType.handshakeResponse, documentId);

  /// Create a handshake response message from a JSON map
  factory HandshakeResponseMessage.fromJson(Map<String, dynamic> json) {
    return HandshakeResponseMessage(
      documentId: json['documentId'] as String,
      snapshot: json['snapshot'] != null
          ? _decodeSnapshot(json['snapshot'] as String)
          : null,
      changes: json['changes'] != null
          ? (json['changes'] as List<dynamic>)
              .map((c) => _decodeChange(c as String))
              .toList()
          : null,
      sessionId: json['sessionId'] as String,
      versionVector: _decodeVersionVector(json['versionVector'] as String),
    );
  }

  /// The snapshot, if present
  final Snapshot? snapshot;

  /// The missing changes, if present
  final List<Change>? changes;

  /// The session ID to which the message refers
  final String sessionId;

  /// The server version vector after applying snapshot and changes
  final VersionVector versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'snapshot': snapshot != null ? _encodeSnapshot(snapshot!) : null,
      'changes': changes?.map(_encodeChange).toList(),
      'sessionId': sessionId,
      'versionVector': _encodeVersionVector(versionVector),
    };
  }

  @override
  String toString() {
    return 'HandshakeResponseMessage(snapshot: $snapshot, '
        'changes: $changes, sessionId: $sessionId,'
        ' versionVector: $versionVector)';
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
      change: _decodeChange(json['change'] as String),
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
      'change': _encodeChange(change),
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
          .map((c) => _decodeChange(c as String))
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
      'changes': changes.map(_encodeChange).toList(),
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
    required this.versionVector,
    this.snapshot,
    this.changes,
  }) : super(MessageType.documentStatus, documentId);

  /// Create a snapshot message from a JSON map
  factory DocumentStatusMessage.fromJson(Map<String, dynamic> json) {
    return DocumentStatusMessage(
      snapshot: json['snapshot'] != null
          ? _decodeSnapshot(json['snapshot'] as String)
          : null,
      documentId: json['documentId'] as String,
      changes: json['changes'] != null
          ? (json['changes'] as List<dynamic>)
              .map((c) => _decodeChange(c as String))
              .toList()
          : null,
      versionVector: _decodeVersionVector(json['versionVector'] as String),
    );
  }

  /// The CRDT snapshot
  final Snapshot? snapshot;

  /// The CRDT changes
  final List<Change>? changes;

  /// The server version vector after applying snapshot and changes
  final VersionVector versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'snapshot': snapshot != null ? _encodeSnapshot(snapshot!) : null,
      'changes': changes?.map(_encodeChange).toList(),
      'versionVector': _encodeVersionVector(versionVector),
    };
  }

  @override
  String toString() {
    return 'DocumentStatusMessage(snapshot: $snapshot, '
        'changes: $changes, documentId: $documentId,'
        ' versionVector: $versionVector)';
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
          ? _decodeVersionVector(json['versionVector'] as String)
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
      'versionVector':
          versionVector != null ? _encodeVersionVector(versionVector!) : null,
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
    this.versionVector,
  }) : super(MessageType.ping, documentId);

  /// Create a ping message from a JSON map
  factory PingMessage.fromJson(Map<String, dynamic> json) {
    return PingMessage(
      timestamp: json['timestamp'] as int,
      documentId: json['documentId'] as String,
      versionVector: json['versionVector'] != null
          ? _decodeVersionVector(json['versionVector'] as String)
          : null,
    );
  }

  /// Timestamp of the ping
  final int timestamp;

  /// The sender's current version vector, if reported.
  ///
  /// Clients piggy-back their version vector on pings so the server can learn
  /// how far each client has advanced and take a snapshot (and prune history)
  /// once every connected client has confirmed a common frontier.
  final VersionVector? versionVector;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'documentId': documentId,
      'timestamp': timestamp,
      if (versionVector != null)
        'versionVector': _encodeVersionVector(versionVector!),
    };
  }

  @override
  String toString() {
    return 'PingMessage(timestamp: $timestamp, documentId: $documentId, '
        'versionVector: $versionVector)';
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
