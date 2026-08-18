part of 'handler.dart';

class _ORSetOperationFactory<T> {
  _ORSetOperationFactory(this.handler);
  final CRDTORSetHandler<T> handler;

  Operation fromBytes(OperationEnvelope env, Uint8List body) {
    if (env.kind == OperationType.kindInsert) {
      return _ORSetAddOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _ORSetRemoveOperation<T>.fromBodyBytes(handler, body);
    }

    throw UnknownOperationKindException(
      handlerType: env.handlerType,
      handlerId: env.handlerId,
      kind: env.kind,
    );
  }
}

/// Add operation for OR-Set
///
/// The tag it adds for the value is the operation's [Operation.stamp], so the
/// body holds nothing but the value.
class _ORSetAddOperation<T> extends Operation {
  _ORSetAddOperation({
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _ORSetAddOperation.fromHandler(
    CRDTORSetHandler<T> handler, {
    required T value,
  }) {
    return _ORSetAddOperation<T>(
      id: handler.id,
      type: handler.insertType,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ORSetAddOperation.fromBodyBytes(
    CRDTORSetHandler<T> handler,
    Uint8List body,
  ) {
    final valueLenRec = UVarint.read(body, offset: 0);
    final valueEnd = valueLenRec.nextOffset + valueLenRec.value;
    if (valueEnd > body.length) {
      throw const FormatException('Truncated OR-Set add value');
    }
    final valueBytes = Uint8List.sublistView(
      body,
      valueLenRec.nextOffset,
      valueEnd,
    );

    return _ORSetAddOperation<T>(
      id: handler.id,
      type: handler.insertType,
      value: handler._valueCodec.decode(valueBytes),
      valueCodec: handler._valueCodec,
    );
  }

  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    final valueBytes = valueCodec.encode(value);
    UVarint.write(valueBytes.length, out);
    out.add(valueBytes);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'value': value,
    };
  }
}

/// Remove operation for OR-Set
/// It tombstones the provided tags that were observed for a value.
class _ORSetRemoveOperation<T> extends Operation {
  _ORSetRemoveOperation({
    required this.value,
    required this.tags,
    required this.removeAll,
    required this.valueCodec,
    required super.id,
    required super.type,
  });
  factory _ORSetRemoveOperation.fromBodyBytes(
    CRDTORSetHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final valueLenRec = UVarint.read(body, offset: offset);
    final valueLen = valueLenRec.value;
    offset = valueLenRec.nextOffset;
    final valueEnd = offset + valueLen;
    if (valueEnd > body.length) {
      throw const FormatException('Truncated OR-Set remove value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, valueEnd);
    final value = handler._valueCodec.decode(valueBytes);
    offset = valueEnd;

    final countRec = UVarint.read(body, offset: offset);
    final count = countRec.value;
    offset = countRec.nextOffset;

    final tags = <OperationId>{};
    for (var i = 0; i < count; i += 1) {
      tags.add(OperationId.readFromBytes(body, offset: offset));
      offset += OperationId.byteLength;
    }

    if (offset >= body.length) {
      throw const FormatException('Missing OR-Set removeAll');
    }
    final removeAll = body[offset] != 0;

    return _ORSetRemoveOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      value: value,
      tags: tags,
      removeAll: removeAll,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ORSetRemoveOperation.fromHandler(
    CRDTORSetHandler<T> handler, {
    required T value,
    required Set<OperationId> tags,
  }) {
    return _ORSetRemoveOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      value: value,
      tags: Set<OperationId>.from(tags),
      removeAll: tags.isEmpty,
      valueCodec: handler._valueCodec,
    );
  }

  final T value;
  final Set<OperationId> tags;
  final bool removeAll;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);

    final valueBytes = valueCodec.encode(value);
    UVarint.write(valueBytes.length, out);
    out.add(valueBytes);

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
      'value': value,
      'tags': tags.map((t) => t.toString()).toList(),
      'removeAll': removeAll,
    };
  }
}
