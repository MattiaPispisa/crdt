part of 'handler.dart';

class _MapInsertOperation<T> extends Operation {
  _MapInsertOperation({
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
    final keyRecord = UVarint.readString(
      body,
      offset: offset,
      what: 'map insert key',
    );
    final key = keyRecord.value;
    offset = keyRecord.nextOffset;

    final valueRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'map insert value',
    );
    final value = handler._valueCodec.decode(valueRecord.value);

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
    UVarint.writeString(key, out);
    UVarint.writeBytes(valueCodec.encode(value), out);

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
  _MapDeleteOperation({
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
    final key = UVarint.readString(
      body,
      offset: 0,
      what: 'map delete key',
    ).value;
    return _MapDeleteOperation<T>.fromHandler(handler, key: key);
  }

  final String key;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.writeString(key, out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'key': key,
      };
}

class _MapUpdateOperation<T> extends Operation {
  _MapUpdateOperation({
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
    final keyRecord = UVarint.readString(
      body,
      offset: offset,
      what: 'map update key',
    );
    final key = keyRecord.value;
    offset = keyRecord.nextOffset;

    final valueRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'map update value',
    );
    final value = handler._valueCodec.decode(valueRecord.value);

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
    UVarint.writeString(key, out);
    UVarint.writeBytes(valueCodec.encode(value), out);

    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'key': key,
        'value': value,
      };
}
