import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [FugueElementID] objects.
///
/// This adapter handles serialization and
/// deserialization of [FugueElementID] objects
/// for Hive storage.
class FugueElementIDAdapter extends TypeAdapter<FugueElementID> {
  @override
  final int typeId = kFugueElementIDAdapter;

  @override
  FugueElementID read(BinaryReader reader) {
    final peerId = reader.read() as PeerId;
    final counter = reader.read() as int?;
    return FugueElementID(peerId, counter);
  }

  @override
  void write(BinaryWriter writer, FugueElementID obj) {
    writer
      ..write(obj.replicaID)
      ..write(obj.counter);
  }
}
