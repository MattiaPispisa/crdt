part of 'handler.dart';

class _RegisterOperationFactory<T> {
  _RegisterOperationFactory(this.handler);

  final CRDTRegisterHandler<T> handler;

  Operation fromBytes(OperationEnvelope env, Uint8List body) {
    if (env.kind == OperationType.kindInsert) {
      return _RegisterSetOperation<T>.fromBodyBytes(handler, body);
    }

    throw UnknownOperationKindException(
      handlerType: env.handlerType,
      handlerId: env.handlerId,
      kind: env.kind,
    );
  }
}

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
    final lenRec = UVarint.read(body, offset: 0);
    final end = lenRec.nextOffset + lenRec.value;
    if (end > body.length) {
      throw const FormatException('Truncated register set value');
    }
    final value = handler._valueCodec.decode(
      Uint8List.sublistView(body, lenRec.nextOffset, end),
    );
    return _RegisterSetOperation<T>.fromHandler(handler, value: value);
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
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'value': value,
      };
}
