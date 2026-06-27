part of 'handler.dart';

class _TextOperationFactory {
  _TextOperationFactory(this.handler);
  final Handler<dynamic> handler;

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
      return _TextInsertOperation.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindDelete) {
      return _TextDeleteOperation.fromBodyBytes(handler, body);
    } else if (env.kind == OperationType.kindUpdate) {
      return _TextUpdateOperation.fromBodyBytes(handler, body);
    }

    return null;
  }
}

class _TextInsertOperation extends Operation {
  const _TextInsertOperation({
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

    final lenRec = UVarint.read(body, offset: offset);
    final len = lenRec.value;
    offset = lenRec.nextOffset;

    final end = offset + len;
    if (end > body.length) {
      throw const FormatException('Truncated text insert');
    }

    final text = utf8.decode(Uint8List.sublistView(body, offset, end));

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
    final textBytes = utf8.encode(text);
    UVarint.write(textBytes.length, out);
    out.add(textBytes);
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
  const _TextDeleteOperation({
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
  const _TextUpdateOperation({
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

    final lenRec = UVarint.read(body, offset: offset);
    final len = lenRec.value;
    offset = lenRec.nextOffset;

    final end = offset + len;
    if (end > body.length) {
      throw const FormatException('Truncated text update');
    }

    final text = utf8.decode(Uint8List.sublistView(body, offset, end));

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
    final textBytes = utf8.encode(text);
    UVarint.write(textBytes.length, out);
    out.add(textBytes);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'text': text,
      };
}
