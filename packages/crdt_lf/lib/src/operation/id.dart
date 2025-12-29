import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// [OperationId] implementation for CRDT
///
/// An [OperationId] uniquely identifies an operation in the CRDT system.
/// It combines a [PeerId] and an [HybridLogicalClock] timestamp
///  to create a globally unique identifier.
class OperationId with Comparable<OperationId> {
  /// Creates a new [OperationId] with the given [PeerId]
  /// and [HybridLogicalClock] timestamp
  OperationId(this.peerId, this.hlc);

  /// Parses an [OperationId] from a string representation
  ///
  /// The format is "peerId@hlc" where [hlc] is in the format "l.c"
  /// ([HybridLogicalClock.toString])
  factory OperationId.parse(String value) {
    final index = value.indexOf('@');
    if (index == -1) {
      throw FormatException('Invalid OpId format: $value');
    }

    final peerId = PeerId.parse(value.substring(0, index));
    final timestamp = HybridLogicalClock.parse(value.substring(index + 1));

    return OperationId(peerId, timestamp);
  }

  /// The peer that created this operation
  final PeerId peerId;

  /// The timestamp when this operation was created
  final HybridLogicalClock hlc;

  /// Returns a string representation of this [OperationId]
  ///
  /// The format is "peerId@hlc" where [hlc] is in the format "l.c"
  /// ([HybridLogicalClock.toString])
  @override
  String toString() => '$peerId@$hlc';

  /// Compares two [OperationId]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OperationId && other.peerId == peerId && other.hlc == hlc;
  }

  late final int _hashCode = Object.hash(peerId, hlc);

  /// Returns a hash code for this [OperationId]
  @override
  int get hashCode => _hashCode;

  /// Compares this [OperationId] with another [OperationId]
  ///
  /// Returns a negative number if this [OperationId] is less than the other,
  /// zero if they are equal, and a positive number
  /// if this [OperationId] is greater.
  ///
  /// The comparison is based on the [hlc] first, then the [peerId].
  @override
  int compareTo(OperationId other) {
    final hlcCompare = hlc.compareTo(other.hlc);
    if (hlcCompare != 0) {
      return hlcCompare;
    }
    return peerId.compareTo(other.peerId);
  }

  /// Checks if this [OperationId] happened before another [OperationId]
  ///
  /// Returns true if this [OperationId] happened before the other [OperationId]
  bool happenedBefore(OperationId other) {
    return compareTo(other) < 0;
  }

  /// Checks if this [OperationId] happened after another [OperationId]
  ///
  /// Returns true if this [OperationId] happened after the other [OperationId]
  bool happenedAfter(OperationId other) {
    return compareTo(other) > 0;
  }

  /// Checks if this [OperationId] happened
  /// after or equal to another [OperationId]
  bool happenedAfterOrEqual(OperationId other) {
    return compareTo(other) >= 0;
  }
}
