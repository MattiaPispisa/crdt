import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/src/adapters/ids.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Hive adapter for [Change] objects.
///
/// This adapter handles serialization and deserialization of [Change] objects
/// for Hive storage.
class ChangeAdapter extends TypeAdapter<Change> {
  /// [useDataAdapter] is used to determine if the payload should be
  /// serialized/deserialized using a custom initialized adapter or the
  /// `json.encode`/`json.decode` method.
  ChangeAdapter({bool useDataAdapter = false})
      : _usePayloadAdapter = useDataAdapter;

  final bool _usePayloadAdapter;

  @override
  final int typeId = kChangeAdapter;

  @override
  Change read(BinaryReader reader) {
    final id = reader.read() as OperationId;
    final hlc = reader.read() as HybridLogicalClock;
    final author = reader.read() as PeerId;

    final depsCount = reader.readInt();
    final deps = <OperationId>{};
    for (var i = 0; i < depsCount; i++) {
      deps.add(reader.read() as OperationId);
    }

    return Change.fromPayload(
      id: id,
      deps: deps,
      hlc: hlc,
      author: author,
      payload: _readPayload(reader),
    );
  }

  Map<String, dynamic> _readPayload(BinaryReader reader) {
    if (!_usePayloadAdapter) {
      return json.decode(reader.readString()) as Map<String, dynamic>;
    }

    final payload = <String, dynamic>{};
    final payloadCount = reader.readInt();
    for (var i = 0; i < payloadCount; i++) {
      final key = reader.readString();
      final value = reader.read();
      payload[key] = value;
    }

    return payload;
  }

  @override
  void write(BinaryWriter writer, Change obj) {
    writer
      ..write(obj.id)
      ..write(obj.hlc)
      ..write(obj.author)
      ..writeInt(obj.deps.length);
    for (final dep in obj.deps) {
      writer.write(dep);
    }

    _writePayload(writer, obj.payload);
  }

  void _writePayload(
    BinaryWriter writer,
    Map<String, dynamic> payload,
  ) {
    if (!_usePayloadAdapter) {
      return writer.writeString(json.encode(payload));
    }

    writer.writeInt(payload.length);
    for (final entry in payload.entries) {
      writer
        ..writeString(entry.key)
        ..write(entry.value);
    }
  }
}
