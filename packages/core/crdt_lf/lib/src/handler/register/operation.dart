part of 'handler.dart';

/// A single "set the value" operation. The register has only one operation
/// kind (encoded as `insert`); conflict resolution is last-writer-wins by HLC.
class _RegisterSetOperation<T> extends Operation {
  _RegisterSetOperation({
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _RegisterSetOperation.fromHandler(
    CRDTRegisterHandler<T> handler, {
    required T value,
  }) {
    return _RegisterSetOperation<T>(
      id: handler.id,
      type: handler.insertType,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _RegisterSetOperation.fromBodyBytes(
    CRDTRegisterHandler<T> handler,
    Uint8List body,
  ) {
    final valueRecord = UVarint.readBytes(
      body,
      offset: 0,
      what: 'register set value',
    );
    final value = handler._valueCodec.decode(valueRecord.value);
    return _RegisterSetOperation<T>.fromHandler(handler, value: value);
  }

  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.writeBytes(valueCodec.encode(value), out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'value': value,
      };
}
