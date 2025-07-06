import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [Snapshot] objects.
///
/// This adapter handles serialization and deserialization of [Snapshot] objects
/// for Hive storage.
class SnapshotAdapter extends TypeAdapter<Snapshot> {
  /// [useDataAdapter] is used to determine if the data should be
  /// serialized/deserialized using a custom initialized adapter or the
  /// `json.encode`/`json.decode` method.
  SnapshotAdapter({
    bool useDataAdapter = false,
  }) : _useDataAdapter = useDataAdapter;

  final bool _useDataAdapter;

  @override
  final int typeId = kSnapshotAdapter;

  @override
  Snapshot read(BinaryReader reader) {
    final id = reader.readString();
    final versionVector = reader.read() as VersionVector;

    // Read data (Map<String, dynamic>)
    final data = _readData(reader);

    return Snapshot(
      id: id,
      versionVector: versionVector,
      data: data,
    );
  }

  Map<String, dynamic> _readData(BinaryReader reader) {
    if (!_useDataAdapter) {
      return json.decode(reader.readString()) as Map<String, dynamic>;
    }

    final data = <String, dynamic>{};
    final dataCount = reader.readInt();
    for (var i = 0; i < dataCount; i++) {
      final key = reader.readString();
      final value = reader.read();
      data[key] = value;
    }

    return data;
  }

  @override
  void write(BinaryWriter writer, Snapshot obj) {
    writer.writeString(obj.id);

    final entries = obj.versionVector.entries.toList();
    writer.writeInt(entries.length);

    for (final entry in entries) {
      writer
        ..writeString(entry.key.id)
        ..writeInt(entry.value.l)
        ..writeInt(entry.value.c);
    }

    _writeData(writer, obj.data);
  }

  void _writeData(BinaryWriter writer, Map<String, dynamic> data) {
    if (!_useDataAdapter) {
      return writer.writeString(json.encode(data));
    }

    writer.writeInt(data.length);
    for (final entry in data.entries) {
      writer
        ..writeString(entry.key)
        ..write(entry.value);
    }
  }
}
