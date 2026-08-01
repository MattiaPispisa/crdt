import 'dart:typed_data';

import 'package:crdt_lf/src/binary/varint.dart';
import 'package:crdt_lf/src/peer_id.dart';

/// The highest element counter each peer has ever used, as recorded in a
/// snapshot.
///
/// A snapshot only carries the elements that are still **live**. Without this
/// table, the counters of elements that a peer created and later deleted would
/// look unused after a reload, and the peer would hand them out a second time.
/// Two different elements would then share an id, which corrupts the tree of
/// every peer that still holds the original as a tombstone.
///
/// The table is appended after the handler's own snapshot payload. Decoders
/// that predate it read their payload and stop, so the trailer is compatible
/// in both directions.
///
/// Layout:
/// - `peerCount: uvarint`
/// - then, per peer: `replicaID: 16 bytes` (PeerId), `maxCounter: uvarint`
class ElementIdFloor {
  /// Appends [floor] to [out].
  static void write(Map<PeerId, int> floor, BytesBuilder out) {
    UVarint.write(floor.length, out);
    for (final entry in floor.entries) {
      out.add(entry.key.toUint8List());
      UVarint.write(entry.value, out);
    }
  }

  /// Decodes the table stored in [bytes] starting at [offset].
  ///
  /// Returns an empty map when [offset] is already at the end of [bytes], i.e.
  /// when the snapshot was written before this trailer existed.
  static Map<PeerId, int> read(Uint8List bytes, {int offset = 0}) {
    if (offset >= bytes.length) {
      return <PeerId, int>{};
    }

    var cursor = offset;
    final countRecord = UVarint.read(bytes, offset: cursor);
    cursor = countRecord.nextOffset;

    final floor = <PeerId, int>{};
    for (var i = 0; i < countRecord.value; i += 1) {
      if (cursor + 16 > bytes.length) {
        throw const FormatException('Truncated element id floor');
      }
      final peerId = PeerId.fromUint8List(bytes, offset: cursor);
      cursor += 16;

      final counterRecord = UVarint.read(bytes, offset: cursor);
      cursor = counterRecord.nextOffset;

      floor[peerId] = counterRecord.value;
    }
    return floor;
  }

  /// Merges [addition] into [target], keeping the higher counter per peer.
  static void mergeInto(Map<PeerId, int> target, Map<PeerId, int> addition) {
    for (final entry in addition.entries) {
      final current = target[entry.key];
      if (current == null || entry.value > current) {
        target[entry.key] = entry.value;
      }
    }
  }
}
