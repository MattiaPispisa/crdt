part of 'handler.dart';

class _ListOperationFactory<T> {
  _ListOperationFactory(this.handler);
  final CRDTListHandler<T> handler;

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
      return _ListInsertOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _ListDeleteOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _ListUpdateOperation<T>.fromBodyBytes(handler, body);
    }

    return null;
  }
}

class _ListInsertOperation<T> extends Operation {
  const _ListInsertOperation({
    required this.index,
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _ListInsertOperation.fromHandler(
    CRDTListHandler<T> handler, {
    required int index,
    required T value,
  }) {
    return _ListInsertOperation(
      id: handler.id,
      type: handler.insertType,
      index: index,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ListInsertOperation.fromBodyBytes(
    CRDTListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;

    final lenRec = UVarint.read(body, offset: offset);
    final len = lenRec.value;
    offset = lenRec.nextOffset;
    final end = offset + len;
    if (end > body.length) {
      throw const FormatException('Truncated list insert value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, end);
    final value = handler._valueCodec.decode(valueBytes);

    return _ListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      index: index,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  final int index;
  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'value': value,
      };

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);
    return out.toBytes();
  }
}

class _ListDeleteOperation<T> extends Operation {
  const _ListDeleteOperation({
    required this.index,
    required this.count,
    required super.id,
    required super.type,
  });

  factory _ListDeleteOperation.fromHandler(
    CRDTListHandler<T> handler, {
    required int index,
    required int count,
  }) {
    return _ListDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      index: index,
      count: count,
    );
  }

  factory _ListDeleteOperation.fromBodyBytes(
    CRDTListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;
    final countRec = UVarint.read(body, offset: offset);
    final count = countRec.value;

    return _ListDeleteOperation<T>.fromHandler(
      handler,
      index: index,
      count: count,
    );
  }

  final int index;
  final int count;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'count': count,
      };

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    UVarint.write(count, out);
    return out.toBytes();
  }
}

class _ListUpdateOperation<T> extends Operation {
  const _ListUpdateOperation({
    required this.index,
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _ListUpdateOperation.fromHandler(
    CRDTListHandler<T> handler, {
    required int index,
    required T value,
  }) {
    return _ListUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      index: index,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _ListUpdateOperation.fromBodyBytes(
    CRDTListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;

    final lenRec = UVarint.read(body, offset: offset);
    final len = lenRec.value;
    offset = lenRec.nextOffset;
    final end = offset + len;
    if (end > body.length) {
      throw const FormatException('Truncated list update value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, end);
    final value = handler._valueCodec.decode(valueBytes);

    return _ListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      index: index,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  final int index;
  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'value': value,
      };

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);
    return out.toBytes();
  }
}
