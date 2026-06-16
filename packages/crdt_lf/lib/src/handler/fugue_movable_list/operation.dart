part of 'handler.dart';

/// Factory for Fugue movable list operations.
class _FugueMovableListOperationFactory<T> {
  _FugueMovableListOperationFactory(this.handler);

  final CRDTFugueMovableListHandler<T> handler;

  /// Decodes an operation from its binary envelope.
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
      return _MovableListInsertOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindMove) {
      return _MovableListMoveOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _MovableListUpdateOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _MovableListDeleteOperation<T>.fromBodyBytes(handler, body);
    }
    return null;
  }
}

/// Inserts a new element with a fresh identity at a Fugue position.
///
/// Layout (body):
/// - identityID: [FugueElementID]
/// - positionID: [FugueElementID]
/// - leftOrigin: [FugueElementID]
/// - rightOrigin: [FugueElementID]
/// - valueLen: uvarint
/// - value: [ValueCodec] bytes
class _MovableListInsertOperation<T> extends Operation {
  _MovableListInsertOperation({
    required this.identityID,
    required this.positionID,
    required this.leftOrigin,
    required this.rightOrigin,
    required this.value,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MovableListInsertOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID identityID,
    required FugueElementID positionID,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required T value,
  }) {
    return _MovableListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      identityID: identityID,
      positionID: positionID,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MovableListInsertOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final identityRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = identityRec.nextOffset;

    final positionRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = positionRec.nextOffset;

    final leftRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = leftRec.nextOffset;

    final rightRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = rightRec.nextOffset;

    final valLenRec = UVarint.read(body, offset: offset);
    offset = valLenRec.nextOffset;
    final valEnd = offset + valLenRec.value;
    if (valEnd > body.length) {
      throw const FormatException(
        'Truncated movable list insert value',
      );
    }
    final value = handler._valueCodec.decode(
      Uint8List.sublistView(body, offset, valEnd),
    );

    return _MovableListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      identityID: identityRec.value,
      positionID: positionRec.value,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      value: value,
      valueCodec: handler._valueCodec,
    );
  }

  final FugueElementID identityID;
  final FugueElementID positionID;
  final FugueElementID leftOrigin;
  final FugueElementID rightOrigin;
  final T value;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(identityID.toBytes())
      ..add(positionID.toBytes())
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);
    return out.toBytes();
  }
}

/// Moves an existing identity to a fresh Fugue position.
///
/// The receiver applies an LWW on the identity's `position` field using [hlc].
///
/// Layout (body):
/// - identityID: [FugueElementID]
/// - newPositionID: [FugueElementID]
/// - leftOrigin: [FugueElementID]
/// - rightOrigin: [FugueElementID]
/// - hlc: 8 bytes ([HybridLogicalClock])
class _MovableListMoveOperation<T> extends Operation {
  _MovableListMoveOperation({
    required this.identityID,
    required this.newPositionID,
    required this.leftOrigin,
    required this.rightOrigin,
    required this.hlc,
    required super.id,
    required super.type,
  });

  factory _MovableListMoveOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID identityID,
    required FugueElementID newPositionID,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required HybridLogicalClock hlc,
  }) {
    return _MovableListMoveOperation<T>(
      id: handler.id,
      type: handler.moveType,
      identityID: identityID,
      newPositionID: newPositionID,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      hlc: hlc,
    );
  }

  factory _MovableListMoveOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final identityRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = identityRec.nextOffset;

    final newPositionRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = newPositionRec.nextOffset;

    final leftRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = leftRec.nextOffset;

    final rightRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = rightRec.nextOffset;

    if (offset + 8 > body.length) {
      throw const FormatException('Truncated movable list move HLC');
    }
    final hlc = HybridLogicalClock.fromUint8List(body, offset: offset);

    return _MovableListMoveOperation<T>(
      id: handler.id,
      type: handler.moveType,
      identityID: identityRec.value,
      newPositionID: newPositionRec.value,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      hlc: hlc,
    );
  }

  final FugueElementID identityID;
  final FugueElementID newPositionID;
  final FugueElementID leftOrigin;
  final FugueElementID rightOrigin;
  final HybridLogicalClock hlc;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(identityID.toBytes())
      ..add(newPositionID.toBytes())
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes())
      ..add(hlc.toUint8List());
    return out.toBytes();
  }
}

/// Updates the value of an existing identity.
///
/// Layout (body):
/// - identityID: [FugueElementID]
/// - hlc: 8 bytes ([HybridLogicalClock])
/// - valueLen: uvarint
/// - value: [ValueCodec] bytes
class _MovableListUpdateOperation<T> extends Operation {
  _MovableListUpdateOperation({
    required this.identityID,
    required this.value,
    required this.hlc,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MovableListUpdateOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID identityID,
    required T value,
    required HybridLogicalClock hlc,
  }) {
    return _MovableListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      identityID: identityID,
      value: value,
      hlc: hlc,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MovableListUpdateOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final identityRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = identityRec.nextOffset;

    if (offset + 8 > body.length) {
      throw const FormatException('Truncated movable list update HLC');
    }
    final hlc = HybridLogicalClock.fromUint8List(body, offset: offset);
    offset += 8;

    final valLenRec = UVarint.read(body, offset: offset);
    offset = valLenRec.nextOffset;
    final valEnd = offset + valLenRec.value;
    if (valEnd > body.length) {
      throw const FormatException(
        'Truncated movable list update value',
      );
    }
    final value = handler._valueCodec.decode(
      Uint8List.sublistView(body, offset, valEnd),
    );

    return _MovableListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      identityID: identityRec.value,
      value: value,
      hlc: hlc,
      valueCodec: handler._valueCodec,
    );
  }

  final FugueElementID identityID;
  final T value;
  final HybridLogicalClock hlc;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(identityID.toBytes())
      ..add(hlc.toUint8List());
    final valBytes = valueCodec.encode(value);
    UVarint.write(valBytes.length, out);
    out.add(valBytes);
    return out.toBytes();
  }
}

/// Marks an identity as deleted.
///
/// Layout (body):
/// - identityID: [FugueElementID]
class _MovableListDeleteOperation<T> extends Operation {
  _MovableListDeleteOperation({
    required this.identityID,
    required super.id,
    required super.type,
  });

  factory _MovableListDeleteOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID identityID,
  }) {
    return _MovableListDeleteOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      identityID: identityID,
    );
  }

  factory _MovableListDeleteOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    final identityRec = FugueElementID.readFromBytes(body);
    return _MovableListDeleteOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      identityID: identityRec.value,
    );
  }

  final FugueElementID identityID;

  @override
  Uint8List toBodyBytes() => identityID.toBytes();
}
