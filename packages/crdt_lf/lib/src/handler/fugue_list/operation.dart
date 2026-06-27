part of 'handler.dart';

/// Factory for Fugue list operations
class _FugueListOperationFactory<T> {
  /// Constructor that initializes the factory
  _FugueListOperationFactory(this.handler);

  /// The handler associated with this factory
  final CRDTFugueListHandler<T> handler;

  /// Creates an operation from bytes.
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
      return _FugueListInsertOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _FugueListDeleteOperation<T>.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _FugueListUpdateOperation<T>.fromBodyBytes(handler, body);
    }

    return null;
  }
}

/// Batch insert operation for the Fugue list
class _FugueListInsertOperation<T> extends Operation {
  /// Constructor that initializes a batch insert operation
  _FugueListInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch insert operation from a handler
  factory _FugueListInsertOperation.fromHandler(
    CRDTFugueListHandler<T> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<_FugueListInsertItem<T>> items,
  }) {
    return _FugueListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  /// Decodes an insert operation body.
  ///
  /// Layout:
  /// - leftOrigin: [FugueElementID] bytes
  /// - rightOrigin: [FugueElementID] bytes
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - id: [FugueElementID] bytes
  ///   - valueLen: uvarint
  ///   - value: [ValueCodec] bytes
  factory _FugueListInsertOperation.fromBodyBytes(
    CRDTFugueListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final leftRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = leftRec.nextOffset;

    final rightRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = rightRec.nextOffset;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueListInsertItem<T>>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;

      final valLenRec = UVarint.read(body, offset: offset);
      offset = valLenRec.nextOffset;
      final valEnd = offset + valLenRec.value;
      if (valEnd > body.length) {
        throw const FormatException('Truncated Fugue list insert value');
      }
      final value = handler._valueCodec.decode(
        Uint8List.sublistView(body, offset, valEnd),
      );
      offset = valEnd;

      items.add(_FugueListInsertItem<T>(id: idRec.value, value: value));
    }

    return _FugueListInsertOperation<T>(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  /// ID of the left origin node for the batch
  final FugueElementID leftOrigin;

  /// ID of the right origin node for the batch
  final FugueElementID rightOrigin;

  /// Items to insert sequentially (first uses [leftOrigin], others chain)
  final List<_FugueListInsertItem<T>> items;

  /// Codec used to encode the inserted values
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.id.toBytes());
      final valBytes = valueCodec.encode(item.value);
      UVarint.write(valBytes.length, out);
      out.add(valBytes);
    }
    return out.toBytes();
  }
}

/// A single item of a batch insert
class _FugueListInsertItem<T> {
  _FugueListInsertItem({
    required this.id,
    required this.value,
  });

  final FugueElementID id;
  final T value;
}

/// Batch delete operation for the Fugue list
class _FugueListDeleteOperation<T> extends Operation {
  /// Constructor that initializes a batch delete operation
  _FugueListDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch delete operation from a handler
  factory _FugueListDeleteOperation.fromHandler(
    CRDTFugueListHandler<T> handler, {
    required List<_FugueListDeleteItem> items,
  }) {
    return _FugueListDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  /// Decodes a delete operation body.
  ///
  /// Layout:
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - nodeID: [FugueElementID] bytes
  factory _FugueListDeleteOperation.fromBodyBytes(
    CRDTFugueListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueListDeleteItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;
      items.add(_FugueListDeleteItem(nodeID: idRec.value));
    }

    return _FugueListDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  /// Items to delete
  final List<_FugueListDeleteItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.nodeID.toBytes());
    }
    return out.toBytes();
  }
}

/// A single item of a batch delete
class _FugueListDeleteItem {
  _FugueListDeleteItem({
    required this.nodeID,
  });

  final FugueElementID nodeID;
}

/// Batch update operation for the Fugue list
class _FugueListUpdateOperation<T> extends Operation {
  /// Constructor that initializes a batch update operation
  _FugueListUpdateOperation({
    required this.items,
    required this.valueCodec,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch update operation from a handler
  factory _FugueListUpdateOperation.fromHandler(
    CRDTFugueListHandler<T> handler, {
    required List<_FugueListUpdateItem<T>> items,
  }) {
    return _FugueListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  /// Decodes an update operation body.
  ///
  /// Layout:
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - nodeID: [FugueElementID] bytes
  ///   - newNodeID: [FugueElementID] bytes
  ///   - valueLen: uvarint
  ///   - value: [ValueCodec] bytes
  factory _FugueListUpdateOperation.fromBodyBytes(
    CRDTFugueListHandler<T> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueListUpdateItem<T>>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;

      final newIdRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = newIdRec.nextOffset;

      final valLenRec = UVarint.read(body, offset: offset);
      offset = valLenRec.nextOffset;
      final valEnd = offset + valLenRec.value;
      if (valEnd > body.length) {
        throw const FormatException('Truncated Fugue list update value');
      }
      final value = handler._valueCodec.decode(
        Uint8List.sublistView(body, offset, valEnd),
      );
      offset = valEnd;

      items.add(
        _FugueListUpdateItem<T>(
          nodeID: idRec.value,
          newNodeID: newIdRec.value,
          value: value,
        ),
      );
    }

    return _FugueListUpdateOperation<T>(
      id: handler.id,
      type: handler.updateType,
      items: items,
      valueCodec: handler._valueCodec,
    );
  }

  /// Items to update
  final List<_FugueListUpdateItem<T>> items;

  /// Codec used to encode the updated values
  final ValueCodec<T> valueCodec;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out
        ..add(item.nodeID.toBytes())
        ..add(item.newNodeID.toBytes());
      final valBytes = valueCodec.encode(item.value);
      UVarint.write(valBytes.length, out);
      out.add(valBytes);
    }
    return out.toBytes();
  }
}

/// A single item of a batch update
class _FugueListUpdateItem<T> {
  _FugueListUpdateItem({
    required this.nodeID,
    required this.newNodeID,
    required this.value,
  });

  final FugueElementID nodeID;
  final FugueElementID newNodeID;
  final T value;
}
