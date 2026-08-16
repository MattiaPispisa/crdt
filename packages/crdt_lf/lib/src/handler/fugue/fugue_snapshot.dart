import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/element_id_floor.dart';

/// Everything a Fugue snapshot blob holds, once decoded.
class FugueSnapshotData<T> {
  /// Creates the decoded form of a blob.
  const FugueSnapshotData({
    required this.nodes,
    required this.stamps,
    required this.floor,
  });

  /// The live elements, in sequence order. Tombstones are not in a snapshot.
  final List<FugueValueNode<T>> nodes;

  /// The last-writer-wins stamps of the elements an update overwrote.
  final Map<FugueElementID, OperationStamp> stamps;

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
///   - `blobLen: uvarint`
///   - `blob: bytes` — the run values, encoded by the handler
/// - `stampCount: uvarint`
/// - repeated `stampCount` times:
///   - `nodeID:` [FugueElementID] bytes
///   - `stamp:` [OperationStamp.byteLength] bytes
/// - `floor:` [ElementIdFloor]
///
/// A **run** is a stretch of live elements, adjacent in sequence order,
/// written by the same peer with consecutive counters. A single peer typing
/// into a document produces one run for the whole text, so the ids cost a
/// handful of bytes instead of one id per element. The writer finds the runs
/// in one linear pass; when the tree starts storing runs of its own they are
/// written out as they already are.
///
/// The values of a run go out as one blob because the handler knows how to
/// frame them: text concatenates WTF-8 and pays nothing per element, a list
/// prefixes each value with its length. See `FugueSequenceHandler.encodeRun`.
class FugueSnapshot {
  /// The version this build writes and is the only one it reads.
  ///
  /// The `Snapshot` wrapper has a version of its own; this one covers the
  /// blob, so the handler can change its layout without touching the wrapper.
  static const int version = 1;

  /// Encodes the live part of [tree] plus [floor].
  ///
  /// [encodeRun] turns the values of one run into a blob; it is the inverse
  /// of the `decodeRun` passed to [read].
  static Uint8List write<T>({
    required FugueTree<T> tree,
    required Map<PeerId, int> floor,
    required Uint8List Function(List<T> values) encodeRun,
  }) {
    final runs = BytesBuilder(copy: false);
    var runCount = 0;

    FugueElementID? startID;
    final values = <T>[];

    void flush() {
      if (startID == null) {
        return;
      }
      runs.add(startID!.toBytes());
      UVarint.write(values.length, runs);
      final blob = encodeRun(values);
      UVarint.write(blob.length, runs);
      runs.add(blob);
      runCount += 1;
    }

    tree.forEachLiveNode((id, value) {
      final continuesRun = startID != null &&
          id.replicaID == startID!.replicaID &&
          id.counter == startID!.counter! + values.length;
      if (!continuesRun) {
        flush();
        startID = id;
        values.clear();
      }
      values.add(value);
    });
    flush();

    final out = BytesBuilder(copy: false)..addByte(version);
    UVarint.write(runCount, out);
    out.add(runs.toBytes());

    final stamps = tree.stamps;
    UVarint.write(stamps.length, out);
    for (final entry in stamps.entries) {
      out
        ..add(entry.key.toBytes())
        ..add(entry.value.toUint8List());
    }

    ElementIdFloor.write(floor, out);
    return out.toBytes();
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
    if (bytes.isEmpty) {
      throw const FormatException('Truncated Fugue snapshot');
    }
    if (bytes[0] != version) {
      throw FormatException(
        'Unsupported Fugue snapshot version: ${bytes[0]} '
        '(this build reads $version)',
      );
    }
    var offset = 1;

    final runCountRec = UVarint.read(bytes, offset: offset);
    offset = runCountRec.nextOffset;

    final nodes = <FugueValueNode<T>>[];
    for (var run = 0; run < runCountRec.value; run += 1) {
      final startRec = FugueElementID.readFromBytes(bytes, offset: offset);
      offset = startRec.nextOffset;

      final lengthRec = UVarint.read(bytes, offset: offset);
      offset = lengthRec.nextOffset;

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
        nodes.add(
          FugueValueNode<T>(
            id: FugueElementID(start.replicaID, start.counter! + i),
            value: values[i],
          ),
        );
      }
    }

    final stampCountRec = UVarint.read(bytes, offset: offset);
    offset = stampCountRec.nextOffset;

    final stamps = <FugueElementID, OperationStamp>{};
    for (var i = 0; i < stampCountRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(bytes, offset: offset);
      offset = idRec.nextOffset;
      stamps[idRec.value] = OperationStamp.fromUint8List(bytes, offset: offset);
      offset += OperationStamp.byteLength;
    }

    return FugueSnapshotData<T>(
      nodes: nodes,
      stamps: stamps,
      floor: ElementIdFloor.read(bytes, offset: offset),
    );
  }
}
