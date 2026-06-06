part of 'handler.dart';

class _ORSetOperationFactory<T> {
  _ORSetOperationFactory(this.handler);
  final CRDTORSetHandler<T> handler;

  Operation? fromBytes(Uint8List operationBytes) {
    final env = OperationEnvelopeCodec.decode(operationBytes);
    if (env.handlerId != handler.id) {
      return null;
    }

    if (env.handlerType != handler.runtimeType.toString()) {
      return null;
    }

    final body = Uint8List.sublistView(operationBytes, env.bodyOffset);
    if (env.kind == OperationType.kindInsert) {
      return _ORSetAddOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _ORSetRemoveOperation<T>.fromBodyBytes(handler, body);
    }

    return null;
  }
}

/// Add operation for OR-Set
/// It adds a new unique tag for the provided value.
class _ORSetAddOperation<T> extends Operation {
  const _ORSetAddOperation({
    required this.value,
    required this.tag,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _ORSetAddOperation.fromHandler(
    CRDTORSetHandler<T> handler, {
    required T value,
    required ORHandlerTag tag,
  }) {
    return _ORSetAddOperation<T>(
      id: handler.id,
      type: OperationType.insert(handler),
      value: value,
      tag: tag,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ORSetAddOperation.fromBodyBytes(
    CRDTORSetHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final valueLenRec = UVarint.read(body, offset: offset);
    final valueLen = valueLenRec.value;
    offset = valueLenRec.nextOffset;
    final valueEnd = offset + valueLen;
    if (valueEnd > body.length) {
      throw const FormatException('Truncated OR-Set add value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, valueEnd);
    final value = handler._valueCodec.decode(valueBytes);
    offset = valueEnd;

    if (offset + 24 > body.length) {
      throw const FormatException('Truncated OR-Set add tag');
    }
    final peerId = PeerId.fromUint8List(body, offset: offset);
    final hlc = HybridLogicalClock.fromUint8List(body, offset: offset + 16);
    final tag = ORHandlerTag(peerId: peerId, hlc: hlc);

    return _ORSetAddOperation<T>(
      id: handler.id,
      type: OperationType.insert(handler),
      value: value,
      tag: tag,
      valueCodec: handler._valueCodec,
    );
  }

  final T value;
  final ORHandlerTag tag;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    final valueBytes = valueCodec.encode(value);
    UVarint.write(valueBytes.length, out);
    out
      ..add(valueBytes)
      ..add(tag.peerId.toUint8List())
      ..add(tag.hlc.toUint8List());
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'value': value,
      'tag': tag.toString(),
    };
  }
}

/// Remove operation for OR-Set
/// It tombstones the provided tags that were observed for a value.
class _ORSetRemoveOperation<T> extends Operation {
  const _ORSetRemoveOperation({
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

    final tags = <ORHandlerTag>{};
    for (var i = 0; i < count; i += 1) {
      if (offset + 24 > body.length) {
        throw const FormatException('Truncated OR-Set remove tags');
      }
      final peerId = PeerId.fromUint8List(body, offset: offset);
      final hlc = HybridLogicalClock.fromUint8List(body, offset: offset + 16);
      tags.add(ORHandlerTag(peerId: peerId, hlc: hlc));
      offset += 24;
    }

    if (offset >= body.length) {
      throw const FormatException('Missing OR-Set removeAll');
    }
    final removeAll = body[offset] != 0;

    return _ORSetRemoveOperation<T>(
      id: handler.id,
      type: OperationType.delete(handler),
      value: value,
      tags: tags,
      removeAll: removeAll,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ORSetRemoveOperation.fromHandler(
    CRDTORSetHandler<T> handler, {
    required T value,
    required Set<ORHandlerTag> tags,
  }) {
    return _ORSetRemoveOperation<T>(
      id: handler.id,
      type: OperationType.delete(handler),
      value: value,
      tags: Set<ORHandlerTag>.from(tags),
      removeAll: tags.isEmpty,
      valueCodec: handler._valueCodec,
    );
  }

  final T value;
  final Set<ORHandlerTag> tags;
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
      out
        ..add(t.peerId.toUint8List())
        ..add(t.hlc.toUint8List());
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
