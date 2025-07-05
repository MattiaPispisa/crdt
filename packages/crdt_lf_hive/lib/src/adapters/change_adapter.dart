import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [Change] objects.
///
/// This adapter handles serialization and deserialization of [Change] objects
/// for Hive storage.
class ChangeAdapter extends TypeAdapter<Change> {
  @override
  final int typeId = 104;

  @override
  Change read(BinaryReader reader) {
    // Read id (OperationId)
    final idPeerIdStr = reader.readString();
    final idHlcL = reader.readInt();
    final idHlcC = reader.readInt();
    final id = OperationId(
      PeerId.parse(idPeerIdStr),
      HybridLogicalClock(l: idHlcL, c: idHlcC),
    );

    // Read deps (Set<OperationId>)
    final depsLength = reader.readInt();
    final deps = <OperationId>{};
    for (var i = 0; i < depsLength; i++) {
      final depPeerIdStr = reader.readString();
      final depHlcL = reader.readInt();
      final depHlcC = reader.readInt();
      deps.add(OperationId(
        PeerId.parse(depPeerIdStr),
        HybridLogicalClock(l: depHlcL, c: depHlcC),
      ));
    }

    // Read hlc (HybridLogicalClock)
    final hlcL = reader.readInt();
    final hlcC = reader.readInt();
    final hlc = HybridLogicalClock(l: hlcL, c: hlcC);

    // Read author (PeerId)
    final authorStr = reader.readString();
    final author = PeerId.parse(authorStr);

    // Read payload (Map<String, dynamic>)
    final payloadJson = reader.readString();
    final payload = Map<String, dynamic>.from(json.decode(payloadJson) as Map);

    return Change.fromPayload(
      id: id,
      deps: deps,
      hlc: hlc,
      author: author,
      payload: payload,
    );
  }

  @override
  void write(BinaryWriter writer, Change obj) {
    // Write id (OperationId)
    writer.writeString(obj.id.peerId.id);
    writer.writeInt(obj.id.hlc.l);
    writer.writeInt(obj.id.hlc.c);

    // Write deps (Set<OperationId>)
    writer.writeInt(obj.deps.length);
    for (final dep in obj.deps) {
      writer.writeString(dep.peerId.id);
      writer.writeInt(dep.hlc.l);
      writer.writeInt(dep.hlc.c);
    }

    // Write hlc (HybridLogicalClock)
    writer.writeInt(obj.hlc.l);
    writer.writeInt(obj.hlc.c);

    // Write author (PeerId)
    writer.writeString(obj.author.id);

    // Write payload (Map<String, dynamic>)
    writer.writeString(json.encode(obj.payload));
  }
} 