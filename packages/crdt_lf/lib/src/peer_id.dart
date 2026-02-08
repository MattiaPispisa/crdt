import 'dart:math';
import 'dart:typed_data';

/// A regular expression for validating [PeerId]s
final peerIdRegex = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// [PeerId] implementation for CRDT
///
/// A [PeerId] uniquely identifies a peer in the CRDT network.
/// It is used to distinguish between different peers when merging changes.
class PeerId with Comparable<PeerId> {
  /// Creates a new [PeerId] with the given identifier
  PeerId._(this.id);

  /// Create an empty [PeerId]
  factory PeerId.empty() {
    return PeerId._('');
  }

  /// Generates a random [PeerId]
  factory PeerId.generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version to 4 (random)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant to 1 (RFC 4122)
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return PeerId.parse('${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}');
  }

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

    final hex = StringBuffer();
    for (var i = 0; i < 16; i += 1) {
      final v = bytes[offset + i];
      hex
        ..write(_hexChar(v >> 4))
        ..write(_hexChar(v & 0x0F));
    }

    final s = hex.toString();
    final uuid = '${s.substring(0, 8)}-'
        '${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-'
        '${s.substring(16, 20)}-'
        '${s.substring(20, 32)}';

    return PeerId.parse(uuid);
  }
  static final Random _random = Random.secure();

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

      if (i + 1 >= id.length) {
        throw FormatException('Invalid PeerId: $id');
      }

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

  static String _hexChar(int value) {
    const digits = '0123456789abcdef';
    return digits[value & 0x0F];
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
