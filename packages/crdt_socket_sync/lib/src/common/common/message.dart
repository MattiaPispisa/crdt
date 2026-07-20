import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';

/// Base64-encodes the binary representation of [vector].
String _encodeVersionVector(VersionVector vector) =>
    base64Encode(vector.toBytes());

/// Decodes a base64-encoded [VersionVector].
VersionVector _decodeVersionVector(String value) =>
    VersionVector.fromBytes(base64Decode(value));

/// Marker interface for a message type's integer code.
///
/// Codes are allocated in ranges so each communication mode and plugin can
/// mint its own without collisions:
///
/// - `0-19`: core protocol ([MessageType])
/// - `20-39`: relay protocol
/// - `100+`: plugins
abstract class MessageTypeValue {
  /// index
  int get value;
}

/// Core protocol message types (range `0-19`).
///
/// [ping], [pong] and [error] are shared by every communication mode; the
/// remaining codes belong to the CRDT-aware sync protocol.
enum MessageType implements MessageTypeValue {
  /// Handshake request message sent from client to server (server-client)
  handshakeRequest(0),

  /// Handshake response message sent from server to client (server-client)
  handshakeResponse(1),

  /// Message containing a CRDT change (server-client)
  change(2),

  /// Message containing a full snapshot (server-client)
  documentStatus(3),

  /// Document status request message sent from client to server (server-client)
  documentStatusRequest(4),

  /// Ping message to check the connection (shared)
  ping(5),

  /// Pong message (shared)
  pong(6),

  /// Error message (shared)
  error(7),

  /// Message containing a set of changes (server-client)
  changes(8);

  const MessageType(this.value);

  @override
  final int value;
}

/// Base class for all messages exchanged over a connection.
///
/// Defines only the frames shared by every communication mode
/// ([PingMessage], [PongMessage], [ErrorMessage]); mode-specific protocols add
/// their own subclasses.
abstract class Message {
  /// Constructor
  const Message(
    this.type,
    this.documentId,
  );

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

  /// Deserialize a shared message ([PingMessage], [PongMessage],
  /// [ErrorMessage]) from a JSON string.
  ///
  /// Returns `null` for every other type code, so it can be chained after a
  /// mode-specific decoder that handles that mode's own frames.
  static Message? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as int;
    if (type == MessageType.ping.value) {
      return PingMessage.fromJson(json);
    }
    if (type == MessageType.pong.value) {
      return PongMessage.fromJson(json);
    }
    if (type == MessageType.error.value) {
      return ErrorMessage.fromJson(json);
    }
    return null;
  }

  @override
  String toString() {
    return 'Message(type: $type, documentId: $documentId)';
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
