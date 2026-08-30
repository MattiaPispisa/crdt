import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_apply.dart';

/// Puts a contiguous chain of runes into a Fugue tree.
///
/// The operation reads its address from the handler it is built for, so the
/// same class serves every handler whose elements are single runes.
///
/// Layout:
/// - `leftOrigin:` [FugueElementID] bytes
/// - `rightOrigin:` [FugueElementID] bytes
/// - `itemsCount:` uvarint
/// - repeated `itemsCount` times:
///   - `id:` [FugueElementID] bytes
///   - `textLen:` uvarint
///   - `text:` wtf8 bytes
class FugueTextInsertOperation extends Operation
    implements FugueSequenceInsert<String> {
  /// Creates an insert of [items] between [leftOrigin] and [rightOrigin].
  FugueTextInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required super.id,
    required super.type,
  });

  /// Creates an insert addressed to [handler].
  factory FugueTextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<FugueTextInsertItem> items,
  }) {
    return FugueTextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
    );
  }

  /// Decodes an insert body addressed to [handler].
  factory FugueTextInsertOperation.fromBodyBytes(
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

    final items = <FugueTextInsertItem>[];
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

      items.add(FugueTextInsertItem(id: idRec.value, text: text));
    }

    return FugueTextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftRec.value,
      rightOrigin: rightRec.value,
      items: items,
    );
  }

  /// The element the chain goes after.
  @override
  final FugueElementID leftOrigin;

  /// The element the chain goes before.
  @override
  final FugueElementID rightOrigin;

  /// The elements to put in, in order.
  @override
  final List<FugueTextInsertItem> items;

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

/// One rune a [FugueTextInsertOperation] puts in.
class FugueTextInsertItem implements FugueInsertItem<String> {
  /// Creates an item giving [id] to [text].
  FugueTextInsertItem({
    required this.id,
    required this.text,
  });

  @override
  final FugueElementID id;

  /// The rune the element holds.
  final String text;

  /// The shared name for [text]: what the element holds.
  @override
  String get value => text;
}

/// Turns elements of a Fugue tree into tombstones.
///
/// Layout:
/// - `itemsCount:` uvarint
/// - repeated `itemsCount` times: `nodeID:` [FugueElementID] bytes
class FugueTextDeleteOperation extends Operation
    implements FugueSequenceDelete {
  /// Creates a delete of [items].
  FugueTextDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  /// Creates a delete addressed to [handler].
  factory FugueTextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<FugueTextDeleteItem> items,
  }) {
    return FugueTextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  /// Decodes a delete body addressed to [handler].
  factory FugueTextDeleteOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <FugueTextDeleteItem>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idRec = FugueElementID.readFromBytes(body, offset: offset);
      offset = idRec.nextOffset;
      items.add(FugueTextDeleteItem(nodeID: idRec.value));
    }

    return FugueTextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  /// The elements to remove.
  @override
  final List<FugueTextDeleteItem> items;

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

/// One element a [FugueTextDeleteOperation] takes out.
class FugueTextDeleteItem implements FugueDeleteItem {
  /// Creates an item naming [nodeID].
  FugueTextDeleteItem({
    required this.nodeID,
  });

  @override
  final FugueElementID nodeID;
}

/// Writes over elements of a Fugue tree, last writer wins.
///
/// Layout:
/// - `itemsCount:` uvarint
/// - repeated `itemsCount` times:
///   - `nodeID:` [FugueElementID] bytes
///   - `textLen:` uvarint
///   - `text:` wtf8 bytes
class FugueTextUpdateOperation extends Operation
    implements FugueSequenceUpdate<String> {
  /// Creates an update of [items].
  FugueTextUpdateOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  /// Creates an update addressed to [handler].
  factory FugueTextUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<FugueTextUpdateItem> items,
  }) {
    return FugueTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  /// Decodes an update body addressed to [handler].
  factory FugueTextUpdateOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;

    final countRec = UVarint.read(body, offset: offset);
    offset = countRec.nextOffset;

    final items = <FugueTextUpdateItem>[];
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

      items.add(FugueTextUpdateItem(nodeID: idRec.value, text: text));
    }

    return FugueTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  /// The elements to write over.
  @override
  final List<FugueTextUpdateItem> items;

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

/// One element a [FugueTextUpdateOperation] writes over.
class FugueTextUpdateItem implements FugueUpdateItem<String> {
  /// Creates an item writing [text] over [nodeID].
  FugueTextUpdateItem({
    required this.nodeID,
    required this.text,
  });

  @override
  final FugueElementID nodeID;

  /// The rune the element should hold.
  final String text;

  /// The shared name for [text]: what the element should hold.
  @override
  String get value => text;
}
