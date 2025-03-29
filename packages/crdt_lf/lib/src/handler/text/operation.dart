part of 'handler.dart';

class _TextOperationFactory {
  final Handler handler;

  _TextOperationFactory(this.handler);

  Operation? fromPayload(dynamic payload) {
    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _TextInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _TextDeleteOperation.fromPayload(payload);
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

  factory _TextInsertOperation.fromHandler(
    Handler handler, {
    required int index,
    required String text,
  }) {
    return _TextInsertOperation(
      id: handler.id,
      type: OperationType.insert(handler),
      index: index,
      text: text,
    );
  }

  final int index;
  final String text;

  @override
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'text': text,
      };

  static _TextInsertOperation fromPayload(dynamic payload) => _TextInsertOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        index: payload['index'],
        text: payload['text'],
      );
}

class _TextDeleteOperation extends Operation {
  const _TextDeleteOperation({
    required this.index,
    required this.count,
    required super.id,
    required super.type,
  });

  factory _TextDeleteOperation.fromHandler(
    Handler handler, {
    required int index,
    required int count,
  }) {
    return _TextDeleteOperation(
      id: handler.id,
      type: OperationType.delete(handler),
      index: index,
      count: count,
    );
  }

  final int index;
  final int count;

  @override
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'count': count,
      };

  static _TextDeleteOperation fromPayload(dynamic payload) => _TextDeleteOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        index: payload['index'],
        count: payload['count'],
      );
}
