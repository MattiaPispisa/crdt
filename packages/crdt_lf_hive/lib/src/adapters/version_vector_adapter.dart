import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [VersionVector] objects.
///
/// This adapter handles serialization and deserialization of [VersionVector] objects
/// for Hive storage.
class VersionVectorAdapter extends TypeAdapter<VersionVector> {
  @override
  final int typeId = 103;

  @override
  VersionVector read(BinaryReader reader) {
    final length = reader.readInt();
    final vector = <PeerId, HybridLogicalClock>{};
    
    for (var i = 0; i < length; i++) {
      final peerIdStr = reader.readString();
      final hlcL = reader.readInt();
      final hlcC = reader.readInt();
      
      final peerId = PeerId.parse(peerIdStr);
      final hlc = HybridLogicalClock(l: hlcL, c: hlcC);
      
      vector[peerId] = hlc;
    }
    
    return VersionVector(vector);
  }

  @override
  void write(BinaryWriter writer, VersionVector obj) {
    final entries = obj.entries.toList();
    writer.writeInt(entries.length);
    
    for (final entry in entries) {
      writer.writeString(entry.key.id);
      writer.writeInt(entry.value.l);
      writer.writeInt(entry.value.c);
    }
  }
} 