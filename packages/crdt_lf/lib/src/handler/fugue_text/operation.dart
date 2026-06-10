part of 'handler.dart';

/// Factory for Fugue operations
class _FugueTextOperationFactory {
  /// Constructor that initializes the factory
  _FugueTextOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler<dynamic> handler;

  /// Creates an operation from bytes.
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
      return _FugueTextInsertOperation.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _FugueTextDeleteOperation.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _FugueTextUpdateOperation.fromBodyBytes(handler, body);
    }

    return null;
  }
}

/// Batch insert operation for the Fugue algorithm
class _FugueTextInsertOperation extends Operation {
  /// Constructor that initializes a batch insert operation
  _FugueTextInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch insert operation from a handler
  factory _FugueTextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<_FugueInsertItem> items,
  }) {
    return _FugueTextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
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
  ///   - textLen: uvarint
  ///   - text: utf8 bytes
  factory _FugueTextInsertOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final leftRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = leftRec.nextOffset;

    final rightRec = FugueElementID.readFromBytes(body, offset: offset);
    offset = rightRec.nextOffset;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueInsertItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;

      final textLenRec = UVarint.read(body, offset: offset);
      offset = textLenRec.nextOffset;
      final textEnd = offset + textLenRec.value;
      if (textEnd > body.length) {
        throw const FormatException('Truncated Fugue insert text');
      }
      final text = utf8.decode(Uint8List.sublistView(body, offset, textEnd));
      offset = textEnd;

      items.add(_FugueInsertItem(id: idRec.value, text: text));
    }

    return _FugueTextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      items: items,
    );
  }

  /// ID of the left origin node for the batch
  final FugueElementID leftOrigin;

  /// ID of the right origin node for the batch
  final FugueElementID rightOrigin;

  /// Items to insert sequentially (first uses [leftOrigin], others chain)
  final List<_FugueInsertItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.id.toBytes());
      final textBytes = utf8.encode(item.text);
      UVarint.write(textBytes.length, out);
      out.add(textBytes);
    }
    return out.toBytes();
  }
}

/// A single item of a batch insert
class _FugueInsertItem {
  _FugueInsertItem({
    required this.id,
    required this.text,
  });

  final FugueElementID id;
  final String text;
}

/// Batch delete operation for the Fugue algorithm
class _FugueTextDeleteOperation extends Operation {
  /// Constructor that initializes a batch delete operation
  _FugueTextDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch delete operation from a handler
  factory _FugueTextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<_FugueDeleteItem> items,
  }) {
    return _FugueTextDeleteOperation(
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
  factory _FugueTextDeleteOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueDeleteItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;
      items.add(_FugueDeleteItem(nodeID: idRec.value));
    }

    return _FugueTextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  /// Items to delete
  final List<_FugueDeleteItem> items;

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
class _FugueDeleteItem {
  _FugueDeleteItem({
    required this.nodeID,
  });

  final FugueElementID nodeID;
}

/// Batch update operation for the Fugue algorithm
class _FugueTextUpdateOperation extends Operation {
  /// Constructor that initializes a batch update operation
  _FugueTextUpdateOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  /// Factory to create a batch update operation from a handler
  factory _FugueTextUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<_FugueUpdateItem> items,
  }) {
    return _FugueTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  /// Decodes an update operation body.
  ///
  /// Layout:
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - nodeID: [FugueElementID] bytes
  ///   - newNodeID: [FugueElementID] bytes
  ///   - textLen: uvarint
  ///   - text: utf8 bytes
  factory _FugueTextUpdateOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <_FugueUpdateItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;

      final newIdRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = newIdRec.nextOffset;

      final textLenRec = UVarint.read(body, offset: offset);
      offset = textLenRec.nextOffset;
      final textEnd = offset + textLenRec.value;
      if (textEnd > body.length) {
        throw const FormatException('Truncated Fugue update text');
      }
      final text = utf8.decode(Uint8List.sublistView(body, offset, textEnd));
      offset = textEnd;

      items.add(
        _FugueUpdateItem(
          nodeID: idRec.value,
          newNodeID: newIdRec.value,
          text: text,
        ),
      );
    }

    return _FugueTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  /// Items to update
  final List<_FugueUpdateItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out
        ..add(item.nodeID.toBytes())
        ..add(item.newNodeID.toBytes());
      final textBytes = utf8.encode(item.text);
      UVarint.write(textBytes.length, out);
      out.add(textBytes);
    }
    return out.toBytes();
  }
}

/// A single item of a batch update
class _FugueUpdateItem {
  _FugueUpdateItem({
    required this.nodeID,
    required this.newNodeID,
    required this.text,
  });

  final FugueElementID nodeID;
  final FugueElementID newNodeID;
  final String text;
}
