// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _FugueRichTextInsertOperation extends Operation
    implements FugueSequenceInsert<String> {
  _FugueRichTextInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required super.id,
    required super.type,
  });

  factory _FugueRichTextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<_FugueInsertItem> items,
  }) {
    return _FugueRichTextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
    );
  }

  factory _FugueRichTextInsertOperation.fromBodyBytes(
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

    return _FugueRichTextInsertOperation(
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

class _FugueInsertItem implements FugueInsertItem<String> {
  _FugueInsertItem({
    required this.id,
    required this.text,
  });

  @override
  final FugueElementID id;

  final String text;

  @override
  String get value => text;
}

class _FugueRichTextDeleteOperation extends Operation
    implements FugueSequenceDelete {
  _FugueRichTextDeleteOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  factory _FugueRichTextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<_FugueDeleteItem> items,
  }) {
    return _FugueRichTextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

  factory _FugueRichTextDeleteOperation.fromBodyBytes(
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

    return _FugueRichTextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      items: items,
    );
  }

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

class _FugueDeleteItem implements FugueDeleteItem {
  _FugueDeleteItem({
    required this.nodeID,
  });

  @override
  final FugueElementID nodeID;
}

class _FugueRichTextUpdateOperation extends Operation
    implements FugueSequenceUpdate<String> {
  _FugueRichTextUpdateOperation({
    required this.items,
    required super.id,
    required super.type,
  });

  factory _FugueRichTextUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required List<_FugueUpdateItem> items,
  }) {
    return _FugueRichTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

  factory _FugueRichTextUpdateOperation.fromBodyBytes(
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

    return _FugueRichTextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      items: items,
    );
  }

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

class _FugueUpdateItem implements FugueUpdateItem<String> {
  _FugueUpdateItem({
    required this.nodeID,
    required this.text,
  });

  @override
  final FugueElementID nodeID;

  final String text;

  @override
  String get value => text;
}

class _FugueRichTextMarkOperation extends Operation {
  _FugueRichTextMarkOperation({
    required this.key,
    required this.value,
    required this.start,
    required this.end,
    required super.id,
    required super.type,
  });

  factory _FugueRichTextMarkOperation.fromHandler(
    CRDTFugueRichTextHandler handler, {
    required String key,
    required Object? value,
    required _Anchor start,
    required _Anchor end,
  }) {
    return _FugueRichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      key: key,
      value: value,
      start: start,
      end: end,
    );
  }

  factory _FugueRichTextMarkOperation.fromBodyBytes(
    CRDTFugueRichTextHandler handler,
    Uint8List body,
  ) {
    final mark = _MarkBody.read(body, 0);
    return _FugueRichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      key: mark.key,
      value: mark.value,
      start: mark.start,
      end: mark.end,
    );
  }

  final String key;
  final Object? value;
  final _Anchor start;
  final _Anchor end;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    _MarkBody.write(out, key: key, value: value, start: start, end: end);
    return out.toBytes();
  }
}
