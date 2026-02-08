import 'dart:typed_data';

import 'package:crdt_lf/src/binary/varint.dart';
import 'package:crdt_lf/src/peer_id.dart';

/// Result of decoding a [FugueElementID] from a byte buffer.
class FugueElementIDReadResult {
  /// Creates a new [FugueElementIDReadResult].
  const FugueElementIDReadResult(this.value, this.nextOffset);

  /// The decoded element id.
  final FugueElementID value;

  /// The offset immediately after the decoded bytes.
  final int nextOffset;
}

/// Represents the ID of an element in the Fugue algorithm
class FugueElementID with Comparable<FugueElementID> {
  /// Constructor that initializes the element ID
  FugueElementID(this.replicaID, this.counter);

  /// Constructor to create a null ID (used for the root)
  factory FugueElementID.nullID() {
    return FugueElementID(
      PeerId.empty(),
      null,
    );
  }

  /// Creates an ID from a JSON object
  factory FugueElementID.fromJson(Map<String, dynamic> json) {
    if (json['counter'] == null) {
      return FugueElementID.nullID();
    }
    return FugueElementID(
      PeerId.parse(json['replicaID'] as String),
      json['counter'] as int?,
    );
  }

  /// Decodes a [FugueElementID] from a buffer that contains exactly its bytes.
  factory FugueElementID.fromBytes(Uint8List bytes) {
    final res = readFromBytes(bytes);
    if (res.nextOffset != bytes.length) {
      throw const FormatException('Trailing bytes after FugueElementID');
    }
    return res.value;
  }

  /// Creates an ID from a string
  factory FugueElementID.parse(String value) {
    if (value == 'null') {
      return FugueElementID.nullID();
    }

    final index = value.indexOf(':');
    if (index == -1) {
      throw FormatException('Invalid FugueElementID format: $value');
    }

    return FugueElementID(
      PeerId.parse(value.substring(0, index)),
      int.parse(value.substring(index + 1)),
    );
  }

  /// ID of the replica that generated this element
  final PeerId replicaID;

  /// Local counter of the replica at the time of element creation
  final int? counter;

  late final int _hashCode = Object.hash(replicaID, counter);

  /// Checks if this is a null ID
  bool get isNull => counter == null;

  /// Compares two element IDs
  @override
  int compareTo(FugueElementID other) {
    if (isNull && other.isNull) {
      return 0;
    }
    if (isNull) {
      return -1;
    }
    if (other.isNull) {
      return 1;
    }

    // Compare first by replicaID
    final replicaCompare = replicaID.compareTo(other.replicaID);
    if (replicaCompare != 0) {
      return replicaCompare;
    }

    // Then by counter
    return counter!.compareTo(other.counter!);
  }

  /// Serializes the ID to JSON format
  Map<String, dynamic> toJson() => {
        'replicaID': replicaID.toString(),
        'counter': counter,
      };

  /// Binary encoding for a [FugueElementID].
  ///
  /// Layout:
  /// - `flag: u8` — 0 if null id, 1 otherwise.
  /// - If `flag == 1`:
  ///   - `replicaID: 16 bytes` (PeerId)
  ///   - `counter: uvarint`
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    if (isNull) {
      out.addByte(0);
      return out.toBytes();
    }
    out
      ..addByte(1)
      ..add(replicaID.toUint8List());
    UVarint.write(counter!, out);
    return out.toBytes();
  }

  /// Decodes a [FugueElementID] from [bytes] starting at [offset].
  static FugueElementIDReadResult readFromBytes(
    Uint8List bytes, {
    int offset = 0,
  }) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated FugueElementID');
    }
    final flag = bytes[offset];
    var cursor = offset + 1;
    if (flag == 0) {
      return FugueElementIDReadResult(FugueElementID.nullID(), cursor);
    }
    if (flag != 1) {
      throw FormatException('Invalid FugueElementID flag: $flag');
    }
    if (cursor + 16 > bytes.length) {
      throw const FormatException('Truncated FugueElementID replicaID');
    }
    final peerId = PeerId.fromUint8List(bytes, offset: cursor);
    cursor += 16;
    final counterRec = UVarint.read(bytes, offset: cursor);
    return FugueElementIDReadResult(
      FugueElementID(peerId, counterRec.value),
      counterRec.nextOffset,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FugueElementID &&
        other.replicaID == replicaID &&
        other.counter == counter;
  }

  @override
  int get hashCode => _hashCode;

  @override
  String toString() {
    if (isNull) {
      return 'null';
    }
    return '$replicaID:$counter';
  }
}
