part of 'handler.dart';

class _MapOperationFactory<T> {
  _MapOperationFactory(this.handler);
  final CRDTMapHandler<T> handler;

  Operation? fromBytes(Uint8List operationBytes) {
    final env = OperationEnvelopeCodec.decode(operationBytes);
    if (env.handlerId != handler.id) {
      return null;
    }

    if (env.handlerType != handler.handlerType) {
      return null;
    }

    final body = Uint8List.sublistView(operationBytes, env.bodyOffset);
    if (env.kind == OperationType.kindInsert) {
      return _MapInsertOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _MapDeleteOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _MapUpdateOperation<T>.fromBodyBytes(handler, body);
    }

    return null;
  }
}

class _MapInsertOperation<T> extends Operation {
  const _MapInsertOperation({
    required this.key,
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MapInsertOperation.fromHandler(
    CRDTMapHandler<T> handler, {
    required String key,
    required T value,
  }) {
    return _MapInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      key: key,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MapInsertOperation.fromBodyBytes(
    CRDTMapHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final keyLenRec = UVarint.read(body, offset: offset);
    final keyLen = keyLenRec.value;
    offset = keyLenRec.nextOffset;
    final keyEnd = offset + keyLen;
    if (keyEnd > body.length) {
      throw const FormatException('Truncated map insert key');
    }
    final key = utf8.decode(Uint8List.sublistView(body, offset, keyEnd));
    offset = keyEnd;

    final valLenRec = UVarint.read(body, offset: offset);
    final valLen = valLenRec.value;
    offset = valLenRec.nextOffset;
    final valEnd = offset + valLen;
    if (valEnd > body.length) {
      throw const FormatException('Truncated map insert value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, valEnd);
    final value = handler._valueCodec.decode(valueBytes);

    return _MapInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      key: key,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  final String key;
  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    final keyBytes = utf8.encode(key);
    UVarint.write(keyBytes.length, out);
    out.add(keyBytes);

    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);

    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'key': key,
        'value': value,
      };
}

class _MapDeleteOperation<T> extends Operation {
  const _MapDeleteOperation({
    required this.key,
    required super.id,
    required super.type,
  });

  factory _MapDeleteOperation.fromHandler(
    CRDTMapHandler<T> handler, {
    required String key,
  }) {
    return _MapDeleteOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      key: key,
    );
  }

  factory _MapDeleteOperation.fromBodyBytes(
    CRDTMapHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final keyLenRec = UVarint.read(body, offset: offset);
    final keyLen = keyLenRec.value;
    offset = keyLenRec.nextOffset;
    final keyEnd = offset + keyLen;
    if (keyEnd > body.length) {
      throw const FormatException('Truncated map delete key');
    }
    final key = utf8.decode(Uint8List.sublistView(body, offset, keyEnd));
    return _MapDeleteOperation<T>.fromHandler(handler, key: key);
  }

  final String key;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    final keyBytes = utf8.encode(key);
    UVarint.write(keyBytes.length, out);
    out.add(keyBytes);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'key': key,
      };
}

class _MapUpdateOperation<T> extends Operation {
  const _MapUpdateOperation({
    required this.key,
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MapUpdateOperation.fromHandler(
    CRDTMapHandler<T> handler, {
    required String key,
    required T value,
  }) {
    return _MapUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      key: key,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MapUpdateOperation.fromBodyBytes(
    CRDTMapHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final keyLenRec = UVarint.read(body, offset: offset);
    final keyLen = keyLenRec.value;
    offset = keyLenRec.nextOffset;
    final keyEnd = offset + keyLen;
    if (keyEnd > body.length) {
      throw const FormatException('Truncated map update key');
    }
    final key = utf8.decode(Uint8List.sublistView(body, offset, keyEnd));
    offset = keyEnd;

    final valLenRec = UVarint.read(body, offset: offset);
    final valLen = valLenRec.value;
    offset = valLenRec.nextOffset;
    final valEnd = offset + valLen;
    if (valEnd > body.length) {
      throw const FormatException('Truncated map update value');
    }
    final valueBytes = Uint8List.sublistView(body, offset, valEnd);
    final value = handler._valueCodec.decode(valueBytes);

    return _MapUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      key: key,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  final String key;
  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    final keyBytes = utf8.encode(key);
    UVarint.write(keyBytes.length, out);
    out.add(keyBytes);

    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);

    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'key': key,
        'value': value,
      };
}
