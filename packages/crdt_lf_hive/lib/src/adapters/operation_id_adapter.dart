import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [OperationId] objects.
///
/// This adapter handles serialization and deserialization of [OperationId] objects
/// for Hive storage.
class OperationIdAdapter extends TypeAdapter<OperationId> {
  @override
  final int typeId = 102;

  @override
  OperationId read(BinaryReader reader) {
    final peerIdStr = reader.readString();
    final hlcL = reader.readInt();
    final hlcC = reader.readInt();
    
    final peerId = PeerId.parse(peerIdStr);
    final hlc = HybridLogicalClock(l: hlcL, c: hlcC);
    
    return OperationId(peerId, hlc);
  }

  @override
  void write(BinaryWriter writer, OperationId obj) {
    writer.writeString(obj.peerId.id);
    writer.writeInt(obj.hlc.l);
    writer.writeInt(obj.hlc.c);
  }
} 