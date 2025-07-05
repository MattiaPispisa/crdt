import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [Snapshot] objects.
///
/// This adapter handles serialization and deserialization of [Snapshot] objects
/// for Hive storage.
class SnapshotAdapter extends TypeAdapter<Snapshot> {
  @override
  final int typeId = 105;

  @override
  Snapshot read(BinaryReader reader) {
    // Read id (String)
    final id = reader.readString();

    // Read versionVector (VersionVector)
    final versionVectorLength = reader.readInt();
    final vector = <PeerId, HybridLogicalClock>{};
    
    for (var i = 0; i < versionVectorLength; i++) {
      final peerIdStr = reader.readString();
      final hlcL = reader.readInt();
      final hlcC = reader.readInt();
      
      final peerId = PeerId.parse(peerIdStr);
      final hlc = HybridLogicalClock(l: hlcL, c: hlcC);
      
      vector[peerId] = hlc;
    }
    
    final versionVector = VersionVector(vector);

    // Read data (Map<String, dynamic>)
    final dataJson = reader.readString();
    final data = Map<String, dynamic>.from(json.decode(dataJson) as Map);

    return Snapshot(
      id: id,
      versionVector: versionVector,
      data: data,
    );
  }

  @override
  void write(BinaryWriter writer, Snapshot obj) {
    // Write id (String)
    writer.writeString(obj.id);

    // Write versionVector (VersionVector)
    final entries = obj.versionVector.entries.toList();
    writer.writeInt(entries.length);
    
    for (final entry in entries) {
      writer.writeString(entry.key.id);
      writer.writeInt(entry.value.l);
      writer.writeInt(entry.value.c);
    }

    // Write data (Map<String, dynamic>)
    writer.writeString(json.encode(obj.data));
  }
} 