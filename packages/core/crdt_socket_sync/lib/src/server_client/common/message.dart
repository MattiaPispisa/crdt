import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';

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

/// Base class for the CRDT-aware sync protocol messages (server-client mode).
///
/// These messages carry decoded CRDT payloads (`Change`, `Snapshot`,
/// `VersionVector`) and use the core type-code range ([MessageType], `0-8`).
abstract class SyncMessage extends Message {
  /// Constructor
  const SyncMessage(super.type, super.documentId);

  /// Create a change message
  factory SyncMessage.change({
    required String documentId,
    required Change change,
  }) {
    return ChangeMessage(
      documentId: documentId,
      change: change,
    );
  }

  /// Create a changes message
  factory SyncMessage.changes({
    required String documentId,
    required List<Change> changes,
  }) {
    return ChangesMessage(documentId: documentId, changes: changes);
  }

  /// Create a document status message
  factory SyncMessage.documentStatus({
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
  factory SyncMessage.documentStatusRequest({
    required String documentId,
    required VersionVector? versionVector,
  }) {
    return DocumentStatusRequestMessage(
      documentId: documentId,
      versionVector: versionVector,
    );
  }

  /// Decodes a sync message from [json].
  ///
  /// Returns `null` for type codes outside the sync protocol, so it can be
  /// chained with other decoders (like [Message.fromJson]).
  static Message? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as int;
    if (type == MessageType.handshakeRequest.value) {
      return HandshakeRequestMessage.fromJson(json);
    }
    if (type == MessageType.handshakeResponse.value) {
      return HandshakeResponseMessage.fromJson(json);
    }
    if (type == MessageType.change.value) {
      return ChangeMessage.fromJson(json);
    }
    if (type == MessageType.changes.value) {
      return ChangesMessage.fromJson(json);
    }
    if (type == MessageType.documentStatus.value) {
      return DocumentStatusMessage.fromJson(json);
    }
    if (type == MessageType.documentStatusRequest.value) {
      return DocumentStatusRequestMessage.fromJson(json);
    }
    return null;
  }
}

/// Handshake request message sent from client to server.
class HandshakeRequestMessage extends SyncMessage {
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
class HandshakeResponseMessage extends SyncMessage {
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
class ChangeMessage extends SyncMessage {
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
class ChangesMessage extends SyncMessage {
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
class DocumentStatusMessage extends SyncMessage {
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
class DocumentStatusRequestMessage extends SyncMessage {
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
