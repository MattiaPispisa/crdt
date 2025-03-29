/// [PeerId] implementation for CRDT
///
/// A [PeerId] uniquely identifies a peer in the CRDT network.
/// It is used to distinguish between different peers when merging changes.

import 'dart:math';

/// A unique identifier for a peer in the CRDT network
class PeerId with Comparable<PeerId> {
  static final Random _random = Random.secure();

  /// Creates a new [PeerId] with the given identifier
  const PeerId(this.id);

  /// Generates a random UUID v4
  factory PeerId.generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version to 4 (random)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant to 1 (RFC 4122)
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

    return PeerId('${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}');
  }

  /// The unique identifier string
  final String id;

  /// Parses a [PeerId] from a string
  factory PeerId.parse(String value) {
    // Check if the string matches UUID v4 format
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value)) {
      throw FormatException('Invalid PeerId format: $value');
    }

    return PeerId(value);
  }

  /// Returns a string representation of this [PeerId]
  @override
  String toString() => id;

  /// Compares two [PeerId]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PeerId && other.id == id;
  }

  /// Returns a hash code for this [PeerId]
  @override
  int get hashCode => id.hashCode;

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
