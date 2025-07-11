import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [OperationId] objects.
///
/// This adapter handles serialization
/// and deserialization of [OperationId] objects
/// for Hive storage.
class OperationIdAdapter extends TypeAdapter<OperationId> {
  /// Creates a new [OperationIdAdapter] with optional [typeId].
  OperationIdAdapter({
    int? typeId,
  }) : _typeId = typeId ?? kOperationIdAdapter;

  final int _typeId;

  @override
  int get typeId => _typeId;

  @override
  OperationId read(BinaryReader reader) {
    final peerId = reader.read() as PeerId;
    final hlc = reader.read() as HybridLogicalClock;

    return OperationId(peerId, hlc);
  }

  @override
  void write(BinaryWriter writer, OperationId obj) {
    writer
      ..write(obj.peerId)
      ..write(obj.hlc);
  }
}
