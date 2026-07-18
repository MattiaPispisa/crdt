import 'dart:convert';
import 'dart:typed_data';

/// Wire protocol shared with the Cloudflare server
/// (`server/src/protocol.ts`). JSON text frames; CRDT binary blobs
/// (crdt_lf `Change`/`Snapshot` bytes) travel as base64 strings and are
/// opaque to the server.
sealed class ProtocolMessage {
  const ProtocolMessage();

  /// Decodes a WebSocket text frame; `null` for unknown message types.
  static ProtocolMessage? decode(String frame) {
    final json = jsonDecode(frame) as Map<String, dynamic>;
    return switch (json['type'] as String?) {
      'welcome' => WelcomeMessage.fromJson(json),
      'push' => PushMessage.fromJson(json),
      'ack' => AckMessage.fromJson(json),
      'change' => ChangeMessage.fromJson(json),
      'snapshot' => SnapshotMessage.fromJson(json),
      'awareness' => AwarenessMessage.fromJson(json),
      'peer_left' => PeerLeftMessage.fromJson(json),
      _ => null,
    };
  }

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());
}

Uint8List _b64Decode(String value) => base64Decode(value);

List<Uint8List> _b64DecodeAll(List<dynamic> values) =>
    values.map((v) => _b64Decode(v as String)).toList();

List<String> _b64EncodeAll(List<Uint8List> blobs) =>
    blobs.map(base64Encode).toList();

/// Server → client, on connect: persisted state plus current peers.
final class WelcomeMessage extends ProtocolMessage {
  const WelcomeMessage({
    required this.snapshot,
    required this.changes,
    required this.seq,
    required this.logLen,
    required this.peers,
    required this.compact,
  });

  factory WelcomeMessage.fromJson(Map<String, dynamic> json) => WelcomeMessage(
    snapshot: json['snapshot'] == null
        ? null
        : _b64Decode(json['snapshot'] as String),
    changes: _b64DecodeAll(json['changes'] as List<dynamic>),
    seq: json['seq'] as int,
    logLen: json['logLen'] as int,
    peers: (json['peers'] as Map<String, dynamic>).map(
      (id, state) => MapEntry(id, state as Map<String, dynamic>),
    ),
    compact: json['compact'] as bool,
  );

  final Uint8List? snapshot;
  final List<Uint8List> changes;
  final int seq;
  final int logLen;
  final Map<String, Map<String, dynamic>> peers;
  final bool compact;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'welcome',
    'snapshot': snapshot == null ? null : base64Encode(snapshot!),
    'changes': _b64EncodeAll(changes),
    'seq': seq,
    'logLen': logLen,
    'peers': peers,
    'compact': compact,
  };
}

/// Client → server: local changes to persist and rebroadcast.
final class PushMessage extends ProtocolMessage {
  const PushMessage({required this.changes});

  factory PushMessage.fromJson(Map<String, dynamic> json) =>
      PushMessage(changes: _b64DecodeAll(json['changes'] as List<dynamic>));

  final List<Uint8List> changes;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'push',
    'changes': _b64EncodeAll(changes),
  };
}

/// Server → client: persistence confirmed up to [seq].
final class AckMessage extends ProtocolMessage {
  const AckMessage({
    required this.seq,
    required this.logLen,
    required this.compact,
  });

  factory AckMessage.fromJson(Map<String, dynamic> json) => AckMessage(
    seq: json['seq'] as int,
    logLen: json['logLen'] as int,
    compact: json['compact'] as bool,
  );

  final int seq;
  final int logLen;
  final bool compact;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ack',
    'seq': seq,
    'logLen': logLen,
    'compact': compact,
  };
}

/// Server → client: changes rebroadcast from another client.
final class ChangeMessage extends ProtocolMessage {
  const ChangeMessage({required this.from, required this.changes});

  factory ChangeMessage.fromJson(Map<String, dynamic> json) => ChangeMessage(
    from: json['from'] as String,
    changes: _b64DecodeAll(json['changes'] as List<dynamic>),
  );

  final String from;
  final List<Uint8List> changes;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'change',
    'from': from,
    'changes': _b64EncodeAll(changes),
  };
}

/// Client → server: compacted snapshot replacing the log up to [upto].
final class SnapshotMessage extends ProtocolMessage {
  const SnapshotMessage({required this.snapshot, required this.upto});

  factory SnapshotMessage.fromJson(Map<String, dynamic> json) =>
      SnapshotMessage(
        snapshot: _b64Decode(json['snapshot'] as String),
        upto: json['upto'] as int,
      );

  final Uint8List snapshot;
  final int upto;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'snapshot',
    'snapshot': base64Encode(snapshot),
    'upto': upto,
  };
}

/// Both directions: ephemeral presence state (never persisted).
///
/// [from] is set only on server → client rebroadcasts.
final class AwarenessMessage extends ProtocolMessage {
  const AwarenessMessage({required this.state, this.from});

  factory AwarenessMessage.fromJson(Map<String, dynamic> json) =>
      AwarenessMessage(
        from: json['from'] as String?,
        state: json['state'] as Map<String, dynamic>,
      );

  final String? from;
  final Map<String, dynamic> state;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'awareness',
    if (from != null) 'from': from,
    'state': state,
  };
}

/// Server → client: a client disconnected.
final class PeerLeftMessage extends ProtocolMessage {
  const PeerLeftMessage({required this.clientId});

  factory PeerLeftMessage.fromJson(Map<String, dynamic> json) =>
      PeerLeftMessage(clientId: json['clientId'] as String);

  final String clientId;

  @override
  Map<String, dynamic> toJson() => {'type': 'peer_left', 'clientId': clientId};
}
