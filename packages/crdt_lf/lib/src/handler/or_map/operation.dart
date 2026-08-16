part of 'handler.dart';

class _ORMapOperationFactory<K, V> {
  _ORMapOperationFactory(this.handler);
  final CRDTORMapHandler<K, V> handler;

  Operation fromBytes(OperationEnvelope env, Uint8List body) {
    if (env.kind == OperationType.kindInsert) {
      return _ORMapPutOperation<K, V>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _ORMapRemoveOperation<K, V>.fromBodyBytes(handler, body);
    }

    throw UnknownOperationKindException(
      handlerType: env.handlerType,
      handlerId: env.handlerId,
      kind: env.kind,
    );
  }
}

/// Put operation for OR-Map
///
/// The tag it adds for the pair is the operation's own [Operation.stamp],
/// carried by the envelope, so the body holds nothing but key and value.
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

    final keyLenRec = UVarint.read(body, offset: offset);
    final keyLen = keyLenRec.value;
    offset = keyLenRec.nextOffset;
    final keyEnd = offset + keyLen;
    if (keyEnd > body.length) {
      throw const FormatException('Truncated OR-Map put key');
    }
    final keyBytes = Uint8List.sublistView(body, offset, keyEnd);
    final key = handler._keyCodec.decode(keyBytes);
    offset = keyEnd;

    final valLenRec = UVarint.read(body, offset: offset);
    final valLen = valLenRec.value;
    offset = valLenRec.nextOffset;
    final valEnd = offset + valLen;
    if (valEnd > body.length) {
      throw const FormatException('Truncated OR-Map put value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, valEnd);
    final value = handler._valueCodec.decode(valueBytes);

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

    final keyBytes = keyCodec.encode(key);
    UVarint.write(keyBytes.length, out);
    out.add(keyBytes);

    final valueBytes = valueCodec.encode(value);
    UVarint.write(valueBytes.length, out);
    out.add(valueBytes);

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
    required Set<OperationStamp> tags,
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
    final keyLenRec = UVarint.read(body, offset: offset);
    final keyLen = keyLenRec.value;
    offset = keyLenRec.nextOffset;
    final keyEnd = offset + keyLen;
    if (keyEnd > body.length) {
      throw const FormatException('Truncated OR-Map remove key');
    }
    final keyBytes = Uint8List.sublistView(body, offset, keyEnd);
    final key = handler._keyCodec.decode(keyBytes);
    offset = keyEnd;

    final countRec = UVarint.read(body, offset: offset);
    final count = countRec.value;
    offset = countRec.nextOffset;

    final tags = <OperationStamp>{};
    for (var i = 0; i < count; i += 1) {
      tags.add(OperationStamp.fromUint8List(body, offset: offset));
      offset += OperationStamp.byteLength;
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
  final Set<OperationStamp> tags;
  final bool removeAll;
  final ValueCodec<K> keyCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);

    final keyBytes = keyCodec.encode(key);
    UVarint.write(keyBytes.length, out);
    out.add(keyBytes);

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
