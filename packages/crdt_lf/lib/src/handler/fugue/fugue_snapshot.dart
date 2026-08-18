import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/element_id_floor.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

/// Everything a Fugue snapshot blob holds, once decoded.
class FugueSnapshotData<T> {
  /// Creates the decoded form of a blob.
  const FugueSnapshotData({
    required this.nodes,
    required this.stamps,
    required this.live,
    required this.livenessStamps,
    required this.floor,
  });

  /// The elements, in sequence order, tombstones among them.
  final List<FugueValueNode<T>> nodes;

  /// The last-writer-wins stamps of the elements an update overwrote.
  final Map<FugueElementID, OperationId> stamps;

  /// Which of [nodes] are still in the sequence: one flag per node, in the
  /// same order, so the two are read together.
  final List<bool> live;

  /// The greatest stamp among the commands that deleted each element.
  ///
  /// Empty in a blob this build wrote: see `FugueSnapshot.write`. An element
  /// with no entry loses to any stamp.
  final Map<FugueElementID, OperationId> livenessStamps;

  /// The highest counter each peer is known to have spent.
  final Map<PeerId, int> floor;
}

/// The binary blob a Fugue sequence handler puts in a snapshot.
///
/// Layout:
/// - `version: u8`
/// - `runCount: uvarint`
/// - repeated `runCount` times:
///   - `startID:` [FugueElementID] bytes
///   - `length: uvarint` — elements `c0 … c0 + length - 1`
///   - `liveness:` `ceil(length / 8)` bytes, bit `i` set when element `i` is
///     still in the sequence, least significant bit first
///   - `blobLen: uvarint`
///   - `blob: bytes` — the run values, encoded by the handler
/// - `stampCount: uvarint`
/// - repeated `stampCount` times:
///   - `nodeID:` [FugueElementID] bytes
///   - `stamp:` [OperationId.byteLength] bytes
/// - `livenessCount: uvarint`
/// - repeated `livenessCount` times: the same pair
/// - `floor:` [ElementIdFloor]
///
/// A **run** is a stretch of elements, adjacent in sequence order, written by
/// the same peer with consecutive counters. A single peer typing into a
/// document produces one run for the whole text, so the ids cost a handful of
/// bytes instead of one id per element. The writer finds the runs in one
/// linear pass.
///
/// Tombstones sit in the runs too, holding the value they were deleted with.
/// An element that leaves the sequence keeps its identity, its place and its
/// content. It also keeps the run whole: a deletion in the middle of one
/// costs a bit of the bitmap rather than a second id.
///
/// The values of a run go out as one blob, framed by the handler that owns
/// them. See `FugueSequenceHandler.encodeRun`.
class FugueSnapshot {
  /// The version this build writes and is the only one it reads.
  ///
  /// It covers this blob only. The `Snapshot` wrapper carries a version of
  /// its own.
  static const int version = 1;

  /// Encodes the whole sequence of [tree], tombstones included, plus [floor].
  ///
  /// [encodeRun] turns the values of one run into a blob; it is the inverse
  /// of the `decodeRun` passed to [read].
  ///
  /// [FugueSnapshotData.livenessStamps] comes back empty from anything this
  /// writes. Nothing reads a liveness stamp, and an entry costs more than the
  /// element it belongs to.
  static Uint8List write<T>({
    required FugueTree<T> tree,
    required Map<PeerId, int> floor,
    required Uint8List Function(List<T> values) encodeRun,
  }) {
    final runs = BytesBuilder(copy: false);
    var runCount = 0;

    FugueElementID? startID;
    final values = <T>[];
    final live = <bool>[];

    void flush() {
      if (startID == null) {
        return;
      }
      runs.add(startID!.toBytes());
      UVarint.write(values.length, runs);
      runs.add(_packLiveness(live));
      final blob = encodeRun(values);
      UVarint.write(blob.length, runs);
      runs.add(blob);
      runCount += 1;
    }

    tree.forEachNode((id, value, {required deleted}) {
      final continuesRun = startID != null &&
          id.replicaID == startID!.replicaID &&
          id.counter == startID!.counter! + values.length;
      if (!continuesRun) {
        flush();
        startID = id;
        values.clear();
        live.clear();
      }
      values.add(value);
      live.add(!deleted);
    });
    flush();

    final out = BytesBuilder(copy: false)..addByte(version);
    UVarint.write(runCount, out);
    out.add(runs.toBytes());

    _writeStamps(tree.stamps, out);
    // Left empty on purpose: nothing reads a liveness stamp yet, and writing
    // one costs 42 bytes per tombstone — 45x the whole blob on a document
    // where half the elements are gone. The table is in the format so the
    // build that does read them can fill it without moving a byte anyone
    // else depends on. A tombstone with no stamp loses to anything, which is
    // the answer a restore wants anyway.
    _writeStamps(const {}, out);

    ElementIdFloor.write(floor, out);
    return out.toBytes();
  }

  static void _writeStamps(
    Map<FugueElementID, OperationId> stamps,
    BytesBuilder out,
  ) {
    UVarint.write(stamps.length, out);
    for (final entry in stamps.entries) {
      out
        ..add(entry.key.toBytes())
        ..add(entry.value.toUint8List());
    }
  }

  static Uint8List _packLiveness(List<bool> live) {
    final packed = Uint8List((live.length + 7) >> 3);
    for (var i = 0; i < live.length; i += 1) {
      if (live[i]) {
        packed[i >> 3] |= 1 << (i & 7);
      }
    }
    return packed;
  }

  /// Decodes a blob written by [write].
  ///
  /// [decodeRun] must return exactly as many values as the run declares.
  ///
  /// Throws a [FormatException] on a version this build does not write, and
  /// on a buffer that ends inside the blob.
  static FugueSnapshotData<T> read<T>(
    Uint8List bytes, {
    required List<T> Function(Uint8List blob, int length) decodeRun,
  }) {
    var offset = SnapshotBlob.read(bytes, version: version, name: 'Fugue');

    final runCountRec = UVarint.read(bytes, offset: offset);
    offset = runCountRec.nextOffset;

    final nodes = <FugueValueNode<T>>[];
    final live = <bool>[];
    for (var run = 0; run < runCountRec.value; run += 1) {
      final startRec = FugueElementID.readFromBytes(bytes, offset: offset);
      offset = startRec.nextOffset;

      final lengthRec = UVarint.read(bytes, offset: offset);
      offset = lengthRec.nextOffset;

      final livenessBytes = (lengthRec.value + 7) >> 3;
      if (offset + livenessBytes > bytes.length) {
        throw const FormatException('Truncated Fugue snapshot liveness');
      }
      final liveness = Uint8List.sublistView(
        bytes,
        offset,
        offset + livenessBytes,
      );
      offset += livenessBytes;

      final blobLenRec = UVarint.read(bytes, offset: offset);
      offset = blobLenRec.nextOffset;
      final blobEnd = offset + blobLenRec.value;
      if (blobEnd > bytes.length) {
        throw const FormatException('Truncated Fugue snapshot run');
      }
      final values = decodeRun(
        Uint8List.sublistView(bytes, offset, blobEnd),
        lengthRec.value,
      );
      offset = blobEnd;

      if (values.length != lengthRec.value) {
        throw FormatException(
          'Fugue snapshot run declares ${lengthRec.value} elements but '
          'decodes to ${values.length}',
        );
      }

      final start = startRec.value;
      for (var i = 0; i < values.length; i += 1) {
        final id = FugueElementID(start.replicaID, start.counter! + i);
        nodes.add(FugueValueNode<T>(id: id, value: values[i]));
        live.add(liveness[i >> 3] & (1 << (i & 7)) != 0);
      }
    }

    final stamps = _readStamps(bytes, offset);
    final livenessStamps = _readStamps(bytes, stamps.nextOffset);

    return FugueSnapshotData<T>(
      nodes: nodes,
      stamps: stamps.value,
      live: live,
      livenessStamps: livenessStamps.value,
      floor: ElementIdFloor.read(bytes, offset: livenessStamps.nextOffset),
    );
  }

  static _StampsReadResult _readStamps(Uint8List bytes, int offset) {
    final countRec = UVarint.read(bytes, offset: offset);
    var cursor = countRec.nextOffset;

    final stamps = <FugueElementID, OperationId>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(bytes, offset: cursor);
      cursor = idRec.nextOffset;
      stamps[idRec.value] = OperationId.readFromBytes(bytes, offset: cursor);
      cursor += OperationId.byteLength;
    }
    return _StampsReadResult(stamps, cursor);
  }
}

/// A decoded stamp table and where it ends.
class _StampsReadResult {
  const _StampsReadResult(this.value, this.nextOffset);

  final Map<FugueElementID, OperationId> value;
  final int nextOffset;
}
