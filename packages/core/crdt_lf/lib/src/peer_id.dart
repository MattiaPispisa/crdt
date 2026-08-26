import 'dart:typed_data';

import 'package:crdt_lf/src/utils/uuid.dart';

/// A regular expression for validating [PeerId]s
final peerIdRegex = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// [PeerId] implementation for CRDT
///
/// A [PeerId] uniquely identifies a peer in the CRDT network.
/// It is used to distinguish between different peers when merging changes.
class PeerId implements Comparable<PeerId> {
  /// Creates a new [PeerId] with the given identifier
  PeerId._(this.id);

  /// Create an empty [PeerId]
  factory PeerId.empty() {
    return PeerId._('');
  }

  /// Generates a random [PeerId]
  factory PeerId.generate() => PeerId.parse(generateUuid());

  /// Parses a [PeerId] from a string
  factory PeerId.parse(String value) {
    // Check if the string matches UUID v4 format
    if (!peerIdRegex.hasMatch(value)) {
      throw FormatException('Invalid PeerId format: $value');
    }

    return PeerId._(value);
  }

  /// Decodes a [PeerId] from a 16-byte buffer.
  ///
  /// Throws a [RangeError] if the buffer is too short.
  factory PeerId.fromUint8List(
    Uint8List bytes, {
    int offset = 0,
  }) {
    if (offset < 0 || offset + 16 > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length - 16, 'offset');
    }

    final hash = _hashBytes(bytes, offset);
    final bucket = _interned[hash];
    if (bucket != null) {
      for (var i = 0; i < bucket.length; i += 1) {
        if (_matchesBytes(bucket[i].id, bytes, offset)) {
          return bucket[i];
        }
      }
    }

    final peer = PeerId._(_renderUuid(bytes, offset));
    if (_internCount < _internLimit) {
      (_interned[hash] ??= <PeerId>[]).add(peer);
      _internCount += 1;
    }
    return peer;
  }

  /// Peers already decoded, bucketed by [_hashBytes].
  ///
  /// A `Map` and not a list scanned linearly: a relay server sees a peer id
  /// per connected client, and a scan would then cost more than the string
  /// it saves.
  static final Map<int, List<PeerId>> _interned = <int, List<PeerId>>{};

  /// How many peers are kept.
  ///
  /// The table is never emptied, so it needs a ceiling: a long-lived server
  /// would otherwise hold every peer it has ever seen. Past the ceiling
  /// decoding still works, it just stops sharing.
  static const int _internLimit = 512;

  static int _internCount = 0;

  /// The first four identifier bytes, packed into one int.
  ///
  /// Four bytes and not a digest of all sixteen: this runs before every
  /// decode, so it has to be cheaper than the string it saves. A UUID v4
  /// carries random bits from its first byte, so four of them spread peers
  /// across buckets well enough; a collision only costs one extra compare in
  /// [_matchesBytes], which settles it exactly. Stays inside 32 bits, which
  /// is exact on every platform this runs on, the web included.
  static int _hashBytes(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Whether [id] is the UUID rendering of the 16 bytes at [offset].
  ///
  /// Compares in place rather than rendering the bytes and comparing the
  /// two strings: a table hit has to stay cheaper than the allocation it
  /// avoids, or interning would buy memory with time.
  static bool _matchesBytes(String id, Uint8List bytes, int offset) {
    if (id.length != 36) {
      return false;
    }

    var cursor = 0;
    for (var i = 0; i < 16; i += 1) {
      if (cursor == 8 || cursor == 13 || cursor == 18 || cursor == 23) {
        cursor += 1;
      }
      final v = bytes[offset + i];
      if (id.codeUnitAt(cursor) != _hexDigits.codeUnitAt(v >> 4)) {
        return false;
      }
      cursor += 1;
      if (cursor == 8 || cursor == 13 || cursor == 18 || cursor == 23) {
        cursor += 1;
      }
      if (id.codeUnitAt(cursor) != _hexDigits.codeUnitAt(v & 0x0F)) {
        return false;
      }
      cursor += 1;
    }
    return true;
  }

  static const String _hexDigits = '0123456789abcdef';

  /// Renders the 16 bytes at [offset] as a UUID string.
  ///
  /// Writes straight into a fixed-length char code array, avoiding a
  /// `StringBuffer` and repeated `substring()` calls.
  /// Layout: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" (36 chars).
  static String _renderUuid(Uint8List bytes, int offset) {
    final codes = Uint16List(36)
      ..[8] = 0x2D // '-'
      ..[13] = 0x2D
      ..[18] = 0x2D
      ..[23] = 0x2D;

    // Fill hex nibbles, skipping the four dash positions.
    var out = 0;
    for (var i = 0; i < 16; i += 1) {
      if (out == 8 || out == 13 || out == 18 || out == 23) out++;
      final v = bytes[offset + i];
      codes[out++] = _hexDigits.codeUnitAt(v >> 4);
      if (out == 8 || out == 13 || out == 18 || out == 23) out++;
      codes[out++] = _hexDigits.codeUnitAt(v & 0x0F);
    }

    // Bytes produced by toUint8List() are already a valid UUID v4 — skip
    // the regex.
    return String.fromCharCodes(codes);
  }

  /// The unique identifier string
  final String id;

  late final int _hashCode = id.hashCode;

  /// Returns a string representation of this [PeerId]
  @override
  String toString() => id;

  /// Encodes this [PeerId] into a new 16-byte buffer.
  Uint8List toUint8List() {
    final out = Uint8List(16);

    var outIndex = 0;
    var i = 0;
    while (i < id.length) {
      final ch = id.codeUnitAt(i);
      if (ch == 0x2D) {
        i += 1;
        continue;
      }

      // Invariant: validated UUID-v4 format guarantees pairs of hex digits
      // between dashes, so we always have a second nibble to read.
      assert(i + 1 < id.length, 'Invalid PeerId: $id');

      final hi = _hexValue(id.codeUnitAt(i));
      final lo = _hexValue(id.codeUnitAt(i + 1));
      out[outIndex] = (hi << 4) | lo;

      outIndex += 1;
      i += 2;
    }

    if (outIndex != 16) {
      throw FormatException('Invalid PeerId: $id');
    }

    return out;
  }

  static int _hexValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) {
      return codeUnit - 0x30;
    }
    if (codeUnit >= 0x61 && codeUnit <= 0x66) {
      return codeUnit - 0x61 + 10;
    }
    if (codeUnit >= 0x41 && codeUnit <= 0x46) {
      return codeUnit - 0x41 + 10;
    }
    throw const FormatException('Invalid hex digit');
  }

  /// Compares two [PeerId]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PeerId && other.id == id;
  }

  /// Returns a hash code for this [PeerId]
  @override
  int get hashCode => _hashCode;

  /// Compares this [PeerId] with another [PeerId]
  ///
  /// Returns a negative number if this [PeerId] is less than the other,
  /// zero if they are equal, and a positive number if this [PeerId] is greater.
  ///
  /// The comparison is based on the string representation of the ID.
  @override
  int compareTo(PeerId other) {
    return id.compareTo(other.id);
  }
}
