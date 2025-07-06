import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';

/// Hive adapter for [PeerId] objects.
///
/// This adapter handles serialization and deserialization of [PeerId] objects
/// for Hive storage.
class PeerIdAdapter extends TypeAdapter<PeerId> {
  @override
  final int typeId = kPeerIdAdapter;

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
