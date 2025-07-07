import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [FugueValueNode] objects.
///
/// This adapter handles serialization and
/// deserialization of [FugueValueNode] objects
/// for Hive storage.
class FugueValueNodeAdapter extends TypeAdapter<FugueValueNode<dynamic>> {
  @override
  final int typeId = kFugueValueNodeAdapter;

  @override
  FugueValueNode<dynamic> read(BinaryReader reader) {
    final id = reader.read() as FugueElementID;
    final value = reader.read();
    return FugueValueNode(id: id, value: value);
  }

  @override
  void write(BinaryWriter writer, FugueValueNode<dynamic> obj) {
    writer
      ..write(obj.id)
      ..write(obj.value);
  }
}
