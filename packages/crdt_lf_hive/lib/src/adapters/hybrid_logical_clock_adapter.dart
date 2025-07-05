import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [HybridLogicalClock] objects.
///
/// This adapter handles serialization and deserialization of [HybridLogicalClock] objects
/// for Hive storage.
class HybridLogicalClockAdapter extends TypeAdapter<HybridLogicalClock> {
  @override
  final int typeId = 101;

  @override
  HybridLogicalClock read(BinaryReader reader) {
    final l = reader.readInt();
    final c = reader.readInt();
    return HybridLogicalClock(l: l, c: c);
  }

  @override
  void write(BinaryWriter writer, HybridLogicalClock obj) {
    writer.writeInt(obj.l);
    writer.writeInt(obj.c);
  }
} 