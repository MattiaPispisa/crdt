import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [Snapshot] objects.
///
/// The snapshot is serialized via [Snapshot.toBytes], which produces a
/// self-describing binary representation (id, version vector and JSON-encoded
/// data). Decoding goes through [Snapshot.fromBytes].
class SnapshotAdapter extends TypeAdapter<Snapshot> {
  /// Creates a new [SnapshotAdapter] with an optional Hive [typeId].
  SnapshotAdapter({
    int? typeId,
  }) : _typeId = typeId ?? kSnapshotAdapter;

  final int _typeId;

  @override
  int get typeId => _typeId;

  @override
  Snapshot read(BinaryReader reader) {
    final bytes = Uint8List.fromList(reader.readByteList());
    return Snapshot.fromBytes(bytes);
  }

  @override
  void write(BinaryWriter writer, Snapshot obj) {
    writer.writeByteList(obj.toBytes());
  }
}
