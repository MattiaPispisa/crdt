part of 'handler.dart';

class _TextInsertOperation extends Operation {
  _TextInsertOperation({
    required this.index,
    required this.text,
    required super.id,
    required super.type,
  });

  factory _TextInsertOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;

    final textRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'text insert',
    );
    final text = Wtf8.decode(textRecord.value);

    return _TextInsertOperation.fromHandler(
      handler,
      index: index,
      text: text,
    );
  }

  factory _TextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required int index,
    required String text,
  }) {
    return _TextInsertOperation(
      id: handler.id,
      type: handler.insertType,
      index: index,
      text: text,
    );
  }

  /// The index of the first character to insert
  final int index;

  /// The text to insert
  final String text;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    UVarint.writeBytes(Wtf8.encode(text), out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'text': text,
      };
}

class _TextDeleteOperation extends Operation {
  _TextDeleteOperation({
    required this.index,
    required this.count,
    required super.id,
    required super.type,
  });

  factory _TextDeleteOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;
    final countRec = UVarint.read(body, offset: offset);
    final count = countRec.value;

    return _TextDeleteOperation.fromHandler(
      handler,
      index: index,
      count: count,
    );
  }

  factory _TextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required int index,
    required int count,
  }) {
    return _TextDeleteOperation(
      id: handler.id,
      type: handler.deleteType,
      index: index,
      count: count,
    );
  }

  /// The index of the first character to delete
  final int index;

  /// The number of characters to delete
  final int count;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    UVarint.write(count, out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'count': count,
      };
}

class _TextUpdateOperation extends Operation {
  _TextUpdateOperation({
    required this.index,
    required this.text,
    required super.id,
    required super.type,
  });

  factory _TextUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required int index,
    required String text,
  }) {
    return _TextUpdateOperation(
      id: handler.id,
      type: handler.updateType,
      index: index,
      text: text,
    );
  }

  factory _TextUpdateOperation.fromBodyBytes(
    Handler<dynamic> handler,
    Uint8List body,
  ) {
    var offset = 0;
    final indexRec = UVarint.read(body, offset: offset);
    final index = indexRec.value;
    offset = indexRec.nextOffset;

    final textRecord = UVarint.readBytes(
      body,
      offset: offset,
      what: 'text update',
    );
    final text = Wtf8.decode(textRecord.value);

    return _TextUpdateOperation.fromHandler(
      handler,
      index: index,
      text: text,
    );
  }

  /// The index of the first character to update
  final int index;

  /// The text to update
  final String text;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(index, out);
    UVarint.writeBytes(Wtf8.encode(text), out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'text': text,
      };
}
