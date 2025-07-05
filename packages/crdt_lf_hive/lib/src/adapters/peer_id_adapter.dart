import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';

/// Hive adapter for [PeerId] objects.
///
/// This adapter handles serialization and deserialization of [PeerId] objects
/// for Hive storage.
class PeerIdAdapter extends TypeAdapter<PeerId> {
  @override
  final int typeId = 100;

  @override
  PeerId read(BinaryReader reader) {
    final id = reader.readString();
    return PeerId.parse(id);
  }

  @override
  void write(BinaryWriter writer, PeerId obj) {
    writer.writeString(obj.id);
  }
} 