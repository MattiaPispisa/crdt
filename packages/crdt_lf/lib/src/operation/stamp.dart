import 'dart:typed_data';

import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// A totally-ordered `(hlc, peerId)` pair minted by the document when an
/// operation is registered.
///
/// Ordering is by clock first and by peer second. The peer is what settles two
/// stamps carrying an identical clock — a case the clock alone cannot order,
/// and where letting the arrival order decide would leave two peers holding
/// different values for the same data.
///
/// An operation kind asks for one by turning on `OperationType.stamped`; the
/// handler then reads it from `Operation.stamp`. The document mints it, so
/// every last-writer-wins handler resolves conflicts by the same rule instead
/// of writing its own. A kind that has no conflict to resolve declares
/// nothing and pays no bytes.
class OperationStamp implements Comparable<OperationStamp> {
  /// Creates a stamp for [hlc] written by [peerId].
  OperationStamp({
    required this.hlc,
    required this.peerId,
  });

  /// Reads a stamp written by [toUint8List] from [bytes] at [offset].
  ///
  /// The cursor advances by [byteLength], which is fixed.
  ///
  /// Throws a [FormatException] when fewer than [byteLength] bytes are left.
  factory OperationStamp.fromUint8List(
    Uint8List bytes, {
    int offset = 0,
  }) {
    if (offset + byteLength > bytes.length) {
      throw const FormatException('Truncated operation stamp');
    }

    return OperationStamp(
      hlc: HybridLogicalClock.fromUint8List(bytes, offset: offset),
      peerId: PeerId.fromUint8List(bytes, offset: offset + 8),
    );
  }

  /// Reads back a stamp written by [toString].
  ///
  /// Throws a [FormatException] on anything [toString] would not have
  /// produced.
  factory OperationStamp.parse(String value) {
    final separator = value.indexOf('@');
    if (separator == -1) {
      throw FormatException('Invalid OperationStamp format: $value');
    }
    return OperationStamp(
      peerId: PeerId.parse(value.substring(0, separator)),
      hlc: HybridLogicalClock.parse(value.substring(separator + 1)),
    );
  }

  /// The width of the encoded form: 8 bytes of clock, then 16 of peer.
  static const int byteLength = 24;

  /// When the write happened, in causal order.
  final HybridLogicalClock hlc;

  /// Who wrote it. Settles two writes that share a clock.
  final PeerId peerId;

  /// Encodes this stamp as [byteLength] bytes: the clock, then the peer.
  Uint8List toUint8List() {
    return Uint8List(byteLength)
      ..setRange(0, 8, hlc.toUint8List())
      ..setRange(8, byteLength, peerId.toUint8List());
  }

  @override
  int compareTo(OperationStamp other) {
    final clockComparison = hlc.compareTo(other.hlc);
    if (clockComparison != 0) {
      return clockComparison;
    }
    return peerId.compareTo(other.peerId);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OperationStamp &&
        other.hlc == hlc &&
        other.peerId == peerId;
  }

  late final int _hashCode = Object.hash(hlc, peerId);

  @override
  int get hashCode => _hashCode;

  @override
  String toString() => '$peerId@$hlc';
}
