import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [VersionVector] objects.
///
/// This adapter handles serialization and deserialization
/// of [VersionVector] objects for Hive storage.
class VersionVectorAdapter extends TypeAdapter<VersionVector> {
  @override
  final int typeId = kVersionVectorAdapter;

  @override
  VersionVector read(BinaryReader reader) {
    final vectorLength = reader.readInt();
    final vector = <PeerId, HybridLogicalClock>{};

    for (var i = 0; i < vectorLength; i++) {
      final peerId = reader.read() as PeerId;
      final hlc = reader.read() as HybridLogicalClock;
      vector[peerId] = hlc;
    }

    return VersionVector(vector);
  }

  @override
  void write(BinaryWriter writer, VersionVector obj) {
    final entries = obj.entries.toList();
    writer.writeInt(entries.length);

    for (final entry in entries) {
      writer
        ..write(entry.key)
        ..write(entry.value);
    }
  }
}
