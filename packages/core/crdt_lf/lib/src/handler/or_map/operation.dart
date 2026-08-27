part of 'handler.dart';

/// Put operation for OR-Map
///
/// The tag it adds for the pair is the operation's [Operation.stamp], so the
/// body holds nothing but key and value.
class _ORMapPutOperation<K, V> extends Operation {
  _ORMapPutOperation({
    required this.key,
    required this.value,
    required this.keyCodec,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _ORMapPutOperation.fromHandler(
    CRDTORMapHandler<K, V> handler, {
    required K key,
    required V value,
  }) {
    return _ORMapPutOperation<K, V>(
      id: handler.id,
      type: handler.insertType,
      key: key,
      value: value,
      keyCodec: handler._keyCodec,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ORMapPutOperation.fromBodyBytes(
    CRDTORMapHandler<K, V> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final keyRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'OR-Map put key',
    );
    final key = handler._keyCodec.decode(keyRecord.value);
    offset = keyRecord.nextOffset;

    final valueRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'OR-Map put value',
    );
    final value = handler._valueCodec.decode(valueRecord.value);

    return _ORMapPutOperation<K, V>(
      id: handler.id,
      type: handler.insertType,
      key: key,
      value: value,
      keyCodec: handler._keyCodec,
      valueCodec: handler._valueCodec,
    );
  }

  final K key;
  final V value;
  final ValueCodec<K> keyCodec;
  final ValueCodec<V> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);

    UVarint.writeBytes(keyCodec.encode(key), out);
    UVarint.writeBytes(valueCodec.encode(value), out);

    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'key': key,
      'value': value,
    };
  }
}

/// Remove operation for OR-Map
/// It tombstones the provided tags that were observed for a key.
class _ORMapRemoveOperation<K, V> extends Operation {
  _ORMapRemoveOperation({
    required this.key,
    required this.tags,
    required this.removeAll,
    required this.keyCodec,
    required super.id,
    required super.type,
  });

  factory _ORMapRemoveOperation.fromHandler(
    CRDTORMapHandler<K, V> handler, {
    required K key,
    required Set<OperationId> tags,
  }) {
    return _ORMapRemoveOperation<K, V>(
      id: handler.id,
      type: handler.deleteType,
      key: key,
      tags: Set.from(tags),
      removeAll: tags.isEmpty,
      keyCodec: handler._keyCodec,
    );
  }

  factory _ORMapRemoveOperation.fromBodyBytes(
    CRDTORMapHandler<K, V> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final keyRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'OR-Map remove key',
    );
    final key = handler._keyCodec.decode(keyRecord.value);
    offset = keyRecord.nextOffset;

    final countRec = UVarint.read(body, offset: offset);
    final count = countRec.value;
    offset = countRec.nextOffset;

    final tags = <OperationId>{};
    for (var i = 0; i < count; i += 1) {
      tags.add(OperationId.readFromBytes(body, offset: offset));
      offset += OperationId.byteLength;
    }

    if (offset >= body.length) {
      throw const FormatException('Missing OR-Map removeAll');
    }
    final removeAll = body[offset] != 0;

    return _ORMapRemoveOperation<K, V>(
      id: handler.id,
      type: handler.deleteType,
      key: key,
      tags: tags,
      removeAll: removeAll,
      keyCodec: handler._keyCodec,
    );
  }

  final K key;
  final Set<OperationId> tags;
  final bool removeAll;
  final ValueCodec<K> keyCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);

    UVarint.writeBytes(keyCodec.encode(key), out);

    UVarint.write(tags.length, out);
    for (final t in tags) {
      out.add(t.toUint8List());
    }

    out.addByte(removeAll ? 1 : 0);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'key': key,
      'tags': tags.map((t) => t.toString()).toList(),
      'removeAll': removeAll,
    };
  }
}
