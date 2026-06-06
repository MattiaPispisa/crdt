import 'dart:typed_data';

import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Packed key representation for an [OperationId].
///
/// This avoids allocating `PeerId`/`HybridLogicalClock`/`OperationId` objects
/// for each change stored in memory.
///
/// Layout is 24 bytes, as defined by [OperationId.byteLength].
class OpIdKey implements Comparable<OpIdKey> {
  OpIdKey._(this._bytes, this._offset);

  /// Creates a key that views 24 bytes from [bytes] starting at [offset].
  factory OpIdKey.view(Uint8List bytes, {int offset = 0}) {
    if (offset < 0 || offset + OperationId.byteLength > bytes.length) {
      throw RangeError.range(
        offset,
        0,
        bytes.length - OperationId.byteLength,
        'offset',
      );
    }
    return OpIdKey._(bytes, offset);
  }

  /// Creates a key by copying 24 bytes from [bytes] starting at [offset].
  factory OpIdKey.copy(Uint8List bytes, {int offset = 0}) {
    final out = Uint8List(OperationId.byteLength)
      ..setRange(0, OperationId.byteLength, bytes, offset);
    return OpIdKey._(out, 0);
  }

  final Uint8List _bytes;
  final int _offset;

  late final int _hashCode = _computeHashCode();

  /// Returns a view of the underlying 24 bytes.
  Uint8List bytesView() {
    return Uint8List.sublistView(
      _bytes,
      _offset,
      _offset + OperationId.byteLength,
    );
  }

  /// Decodes this key into an [OperationId].
  OperationId toOperationId() {
    return OperationId.fromUint8List(_bytes, offset: _offset);
  }

  /// Decodes the peer id.
  PeerId peerId() {
    return PeerId.fromUint8List(_bytes, offset: _offset);
  }

  /// Decodes the HLC.
  HybridLogicalClock hlc() {
    return HybridLogicalClock.fromUint8List(_bytes, offset: _offset + 16);
  }

  /// Returns true if this operation happened after or equal to [other].
  bool happenedAfterOrEqual(OpIdKey other) {
    return compareTo(other) >= 0;
  }

  /// Returns true if this operation happened after [other].
  bool happenedAfter(OpIdKey other) {
    return compareTo(other) > 0;
  }

  /// Returns true if this operation happened before [other].
  bool happenedBefore(OpIdKey other) {
    return compareTo(other) < 0;
  }

  @override
  int compareTo(OpIdKey other) {
    // Compare HLC bytes (big endian) without 64-bit bitwise ops.
    for (var i = 16; i < 24; i += 1) {
      final a = _bytes[_offset + i];
      final b = other._bytes[other._offset + i];
      if (a != b) {
        return a < b ? -1 : 1;
      }
    }

    for (var i = 0; i < 16; i += 1) {
      final a = _bytes[_offset + i];
      final b = other._bytes[other._offset + i];
      if (a != b) {
        return a < b ? -1 : 1;
      }
    }

    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! OpIdKey) {
      return false;
    }

    for (var i = 0; i < OperationId.byteLength; i += 1) {
      if (_bytes[_offset + i] != other._bytes[other._offset + i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => _hashCode;

  int _computeHashCode() {
    // FNV-1a 32-bit, small + fast for 24 bytes.
    var hash = 0x811C9DC5;
    for (var i = 0; i < OperationId.byteLength; i += 1) {
      hash ^= _bytes[_offset + i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  String toString() {
    return toOperationId().toString();
  }
}
