import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [Change] objects.
///
/// The change is serialized via [Change.toBytes], which produces a
/// self-describing binary representation (schema version, id, deps and
/// payload). Decoding goes through [Change.fromBytes].
class ChangeAdapter extends TypeAdapter<Change> {
  /// Creates a new [ChangeAdapter] with an optional Hive [typeId].
  ChangeAdapter({
    int? typeId,
  }) : _typeId = typeId ?? kChangeAdapter;

  final int _typeId;

  @override
  int get typeId => _typeId;

  @override
  Change read(BinaryReader reader) {
    final bytes = Uint8List.fromList(reader.readByteList());
    return Change.fromBytes(bytes);
  }

  @override
  void write(BinaryWriter writer, Change obj) {
    writer.writeByteList(obj.toBytes());
  }
}
