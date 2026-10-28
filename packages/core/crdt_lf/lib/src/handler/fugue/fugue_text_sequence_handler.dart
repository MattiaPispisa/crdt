// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_apply.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';

abstract base class FugueTextSequenceHandler<V, S extends FugueState<String, V>>
    extends FugueSequenceHandler<String, V, S> {
  FugueTextSequenceHandler(super.doc, super.id, {required super.spec});

  @override
  OperationDecoders get operationDecoders => _textDecoders;

  late final OperationDecoders _textDecoders = {
    OperationType.kindInsert: (body) =>
        FugueTextInsertOperation.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        FugueTextDeleteOperation.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        FugueTextUpdateOperation.fromBodyBytes(this, body),
  };

  void insert(int index, String text);

  /// Overwrites the elements starting at [index] with [text], keeping the
  /// identity of each one.
  ///
  /// Two peers updating the same element converge on one of the two values
  /// instead of keeping both, anchors taken with [stablePositionAt] keep
  /// resolving, and nothing is added to the tree. An update loses against a
  /// concurrent deletion of the same element, and stops at the end of the
  /// text instead of inserting.
  ///
  /// [index] and the length of [text] are counted in **runes**, like every
  /// other positional API of this handler.
  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final runes = text.runes.toList();
    final items = <FugueTextUpdateItem>[];
    for (var i = 0; i < runes.length; i++) {
      final nodeID = nodeAt(index + i);
      if (nodeID.isNull) {
        // Past the end of the text: there is nothing left to overwrite.
        break;
      }
      items.add(
        FugueTextUpdateItem(
          nodeID: nodeID,
          text: String.fromCharCode(runes[i]),
        ),
      );
    }

    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      FugueTextUpdateOperation.fromHandler(this, items: items),
    );
  }

  /// Gets the length of the text, **in runes**
  int get length => elementCount;

  @override
  void applyToTree(
    FugueTree<String> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (!applyFugueSequenceOperation<String>(tree, operation, sink: sink)) {
      sink?.add(const SequenceDelta<String>.empty());
    }
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is FugueTextInsertOperation) {
      for (final item in operation.items) {
        yield item.id;
      }
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return FugueTextDeleteOperation.fromHandler(
      this,
      items: nodeIDs.map((id) => FugueTextDeleteItem(nodeID: id)).toList(),
    );
  }

  @override
  Operation buildInsertOperation({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<({FugueElementID id, String value})> items,
  }) {
    return FugueTextInsertOperation.fromHandler(
      this,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: [
        for (final item in items)
          FugueTextInsertItem(id: item.id, text: item.value),
      ],
    );
  }

  @override
  Operation buildUpdateOperation(
    List<({FugueElementID nodeID, String value})> items,
  ) {
    return FugueTextUpdateOperation.fromHandler(
      this,
      items: [
        for (final item in items)
          FugueTextUpdateItem(nodeID: item.nodeID, text: item.value),
      ],
    );
  }

  /// Writes the run as plain WTF-8, one sequence per element and nothing
  /// else: an element is one rune, and a rune is one WTF-8 sequence, so the
  /// blob is self-delimiting and ASCII text costs one byte per character.
  @override
  Uint8List encodeRun(List<String> values) => Wtf8.encodeAll(values);

  @override
  List<String> decodeRun(Uint8List blob, int length) =>
      Wtf8.decodeCodePoints(blob);
}

void applyFugueTextChange(
  FugueTextSequenceHandler<Object?, FugueState<String, Object?>> handler,
  String current,
  String newText,
) {
  final diff = myersDiff(current, newText);

  // Track offset as text length changes during operations
  var offset = 0;

  for (final segment in diff) {
    switch (segment.op) {
      case DiffOp.equal:
        break;
      case DiffOp.insert:
        handler.insert(segment.oldStart + offset, segment.text);
        offset += segment.newEnd - segment.newStart;
      case DiffOp.remove:
        final count = segment.oldEnd - segment.oldStart;
        handler.delete(segment.oldStart + offset, count);
        offset -= count;
    }
  }
}

/// Batch insert operation for the Fugue algorithm
class FugueTextInsertOperation extends Operation
    implements FugueSequenceInsert<String> {
  FugueTextInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required super.id,
    required super.type,
  });

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

  /// One element per rune of [text], with fresh ids.
  factory FugueTextInsertOperation.ofText(
    FugueSequenceHandler<String, Object?, FugueState<String, Object?>>
        handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required String text,
  }) {
    return FugueTextInsertOperation.fromHandler(
      handler,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: [
        for (final rune in text.runes)
          FugueTextInsertItem(
            id: FugueElementID(handler.doc.peerId, handler.nextCounter()),
            text: String.fromCharCode(rune),
          ),
      ],
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

  @override
  final FugueElementID leftOrigin;

  @override
  final FugueElementID rightOrigin;

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

class FugueTextInsertItem implements FugueInsertItem<String> {
  FugueTextInsertItem({
    required this.id,
    required this.text,
  });

  @override
  final FugueElementID id;

  final String text;

  @override
  String get value => text;
}

/// Batch delete operation for the Fugue algorithm
class FugueTextDeleteOperation extends Operation
    implements FugueSequenceDelete {
  FugueTextDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

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

  /// Decodes a delete operation body.
  ///
  /// Layout:
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - nodeID: [FugueElementID] bytes
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

class FugueTextDeleteItem implements FugueDeleteItem {
  FugueTextDeleteItem({
    required this.nodeID,
  });

  @override
  final FugueElementID nodeID;
}

/// Batch update operation for the Fugue algorithm
class FugueTextUpdateOperation extends Operation
    implements FugueSequenceUpdate<String> {
  FugueTextUpdateOperation({
    required this.items,
    required super.id,
    required super.type,
  });

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

  /// Decodes an update operation body.
  ///
  /// Layout:
  /// - itemsCount: uvarint
  /// - repeated `itemsCount` times:
  ///   - nodeID: [FugueElementID] bytes
  ///   - textLen: uvarint
  ///   - text: wtf8 bytes
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

class FugueTextUpdateItem implements FugueUpdateItem<String> {
  FugueTextUpdateItem({
    required this.nodeID,
    required this.text,
  });

  @override
  final FugueElementID nodeID;

  final String text;

  @override
  String get value => text;
}
