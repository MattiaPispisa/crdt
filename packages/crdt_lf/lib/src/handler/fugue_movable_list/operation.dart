part of 'handler.dart';

/// Factory for Fugue movable list operations.
class _FugueMovableListOperationFactory<T> {
  _FugueMovableListOperationFactory(this.handler);

  final CRDTFugueMovableListHandler<T> handler;

  late final OperationDecoders _decoders = {
    OperationType.kindInsert: (body) =>
        _MovableListInsertOperation<T>.fromBodyBytes(handler, body),
    OperationType.kindMove: (body) =>
        _MovableListMoveOperation<T>.fromBodyBytes(handler, body),
    OperationType.kindUpdate: (body) =>
        _MovableListUpdateOperation<T>.fromBodyBytes(handler, body),
    OperationType.kindDelete: (body) =>
        _MovableListDeleteOperation<T>.fromBodyBytes(handler, body),
  };

  /// Decodes an operation from its binary envelope.
  Operation fromBytes(OperationEnvelope env, Uint8List body) =>
      decodeOperation(env, body, _decoders);
}

/// Batch insert: introduces a contiguous run of new identities anchored at
/// the same Fugue origin pair, chaining additional items to the previously
/// inserted one (Fugue's non-interleaving property).
///
/// Layout (body):
/// - leftOrigin: [FugueElementID]
/// - rightOrigin: [FugueElementID]
/// - itemsCount: uvarint
/// - repeated `itemsCount` times:
///   - identityID: [FugueElementID]
///   - positionID: [FugueElementID]
///   - valueLen: uvarint
///   - value: [ValueCodec] bytes
class _MovableListInsertOperation<T> extends Operation {
  _MovableListInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MovableListInsertOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<_MovableListInsertItem<T>> items,
  }) {
    return _MovableListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MovableListInsertOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final leftRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = leftRec.nextOffset;

    final rightRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = rightRec.nextOffset;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_MovableListInsertItem<T>>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final identityRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = identityRec.nextOffset;

      final positionRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = positionRec.nextOffset;

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
      offset = valEnd;

      items.add(
        _MovableListInsertItem<T>(
          identityID: identityRec.value,
          positionID: positionRec.value,
          value: value,
        ),
      );
    }

    return _MovableListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  /// Origin used by the first item (subsequent items chain to the previous
  /// item's `positionID`, sharing the same [rightOrigin]).
  final FugueElementID leftOrigin;
  final FugueElementID rightOrigin;
  final List<_MovableListInsertItem<T>> items;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    UVarint.write(items.length, out);
    for (final item in items) {
      out
        ..add(item.identityID.toBytes())
        ..add(item.positionID.toBytes());
      final valBytes = valueCodec.encode(item.value);
      UVarint.write(valBytes.length, out);
      out.add(valBytes);
    }
    return out.toBytes();
  }
}

/// A single item in a batch insert.
class _MovableListInsertItem<T> {
  _MovableListInsertItem({
    required this.identityID,
    required this.positionID,
    required this.value,
  });

  final FugueElementID identityID;
  final FugueElementID positionID;
  final T value;
}

/// Single-element move. Range moves are intentionally not supported — they
/// are an open problem (see Kleppmann, PaPoC 2020, §4).
///
/// Layout (body):
/// - identityID: [FugueElementID]
/// - newPositionID: [FugueElementID]
/// - leftOrigin: [FugueElementID]
/// - rightOrigin: [FugueElementID]
///
/// The mark this move is resolved against is the operation's
/// [Operation.stamp], not part of the body.
class _MovableListMoveOperation<T> extends Operation {
  _MovableListMoveOperation({
    required this.identityID,
    required this.newPositionID,
    required this.leftOrigin,
    required this.rightOrigin,
    required super.id,
    required super.type,
  });

  factory _MovableListMoveOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required FugueElementID identityID,
    required FugueElementID newPositionID,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    return _MovableListMoveOperation<T>(
      id: handler.id,
      type: handler.moveType,
      identityID: identityID,
      newPositionID: newPositionID,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
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

    return _MovableListMoveOperation<T>(
      id: handler.id,
      type: handler.moveType,
      identityID: identityRec.value,
      newPositionID: newPositionRec.value,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
    );
  }

  final FugueElementID identityID;
  final FugueElementID newPositionID;
  final FugueElementID leftOrigin;
  final FugueElementID rightOrigin;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(identityID.toBytes())
      ..add(newPositionID.toBytes())
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    return out.toBytes();
  }
}

/// Batch update: every item shares the operation's [Operation.stamp], so the
/// whole batch is applied or rejected atomically against each identity's
/// current value stamp.
///
/// Layout (body):
/// - itemsCount: uvarint
/// - repeated `itemsCount` times:
///   - identityID: [FugueElementID]
///   - valueLen: uvarint
///   - value: [ValueCodec] bytes
class _MovableListUpdateOperation<T> extends Operation {
  _MovableListUpdateOperation({
    required this.items,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  factory _MovableListUpdateOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required List<_MovableListUpdateItem<T>> items,
  }) {
    return _MovableListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  factory _MovableListUpdateOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_MovableListUpdateItem<T>>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final identityRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = identityRec.nextOffset;

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
      offset = valEnd;

      items.add(
        _MovableListUpdateItem<T>(
          identityID: identityRec.value,
          value: value,
        ),
      );
    }

    return _MovableListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  final List<_MovableListUpdateItem<T>> items;
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.identityID.toBytes());
      final valBytes = valueCodec.encode(item.value);
      UVarint.write(valBytes.length, out);
      out.add(valBytes);
    }
    return out.toBytes();
  }
}

/// A single item in a batch update.
class _MovableListUpdateItem<T> {
  _MovableListUpdateItem({
    required this.identityID,
    required this.value,
  });

  final FugueElementID identityID;
  final T value;
}

/// Batch delete.
///
/// Layout (body):
/// - itemsCount: uvarint
/// - repeated `itemsCount` times:
///   - identityID: [FugueElementID]
class _MovableListDeleteOperation<T> extends Operation {
  _MovableListDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  factory _MovableListDeleteOperation.fromHandler(
    CRDTFugueMovableListHandler<T> handler, {
    required List<_MovableListDeleteItem> items,
  }) {
    return _MovableListDeleteOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  factory _MovableListDeleteOperation.fromBodyBytes(
    CRDTFugueMovableListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_MovableListDeleteItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final identityRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = identityRec.nextOffset;
      items.add(_MovableListDeleteItem(identityID: identityRec.value));
    }

    return _MovableListDeleteOperation<T>(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  final List<_MovableListDeleteItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.identityID.toBytes());
    }
    return out.toBytes();
  }
}

/// A single item in a batch delete.
class _MovableListDeleteItem {
  _MovableListDeleteItem({required this.identityID});

  final FugueElementID identityID;
}
