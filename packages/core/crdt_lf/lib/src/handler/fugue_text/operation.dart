part of 'handler.dart';

/// Batch insert operation for the Fugue algorithm
class _FugueTextInsertOperation extends Operation
    implements FugueSequenceInsert<String> {
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
  ///   - text: wtf8 bytes
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

      final textRecord = UVarint.readBytes(
        body,
        offset: offset,
        what: 'Fugue insert text',
      );
      final text = Wtf8.decode(textRecord.value);
      offset = textRecord.nextOffset;

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
  @override
  final FugueElementID leftOrigin;

  /// ID of the right origin node for the batch
  @override
  final FugueElementID rightOrigin;

  /// Items to insert sequentially (first uses [leftOrigin], others chain)
  @override
  final List<_FugueInsertItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false)
      ..add(leftOrigin.toBytes())
      ..add(rightOrigin.toBytes());
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.id.toBytes());
      UVarint.writeBytes(Wtf8.encode(item.text), out);
    }
    return out.toBytes();
  }
}

/// A single item of a batch insert
class _FugueInsertItem implements FugueInsertItem<String> {
  _FugueInsertItem({
    required this.id,
    required this.text,
  });

  @override
  final FugueElementID id;

  final String text;

  /// The shared name for [text]: what the element holds.
  @override
  String get value => text;
}

/// Batch delete operation for the Fugue algorithm
class _FugueTextDeleteOperation extends Operation
    implements FugueSequenceDelete {
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
  @override
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
class _FugueDeleteItem implements FugueDeleteItem {
  _FugueDeleteItem({
    required this.nodeID,
  });

  @override
  final FugueElementID nodeID;
}

/// Batch update operation for the Fugue algorithm
class _FugueTextUpdateOperation extends Operation
    implements FugueSequenceUpdate<String> {
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
  ///   - textLen: uvarint
  ///   - text: wtf8 bytes
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

      final textRecord = UVarint.readBytes(
        body,
        offset: offset,
        what: 'Fugue update text',
      );
      final text = Wtf8.decode(textRecord.value);
      offset = textRecord.nextOffset;

      items.add(_FugueUpdateItem(nodeID: idRec.value, text: text));
    }

    return _FugueTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  /// Items to update
  @override
  final List<_FugueUpdateItem> items;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(items.length, out);
    for (final item in items) {
      out.add(item.nodeID.toBytes());
      UVarint.writeBytes(Wtf8.encode(item.text), out);
    }
    return out.toBytes();
  }
}

/// A single item of a batch update
class _FugueUpdateItem implements FugueUpdateItem<String> {
  _FugueUpdateItem({
    required this.nodeID,
    required this.text,
  });

  @override
  final FugueElementID nodeID;

  final String text;

  /// The shared name for [text]: what the element should hold.
  @override
  String get value => text;
}
