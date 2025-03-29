part of 'handler.dart';

// TODO: terminare parte di list

class _ListOperationFactory {
  final Handler handler;

  _ListOperationFactory(this.handler);

  Operation? fromPayload(dynamic payload) {
    if (payload['type'] == OperationType.insert(handler)) {
      return _ListInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler)) {
      return _ListDeleteOperation.fromPayload(payload);
    }

    return null;
  }
}

class _ListInsertOperation extends Operation {
  const _ListInsertOperation({
    required this.index,
    required this.text,
    required super.id,
    required super.type,
  });

  factory _ListInsertOperation.fromHandler(
    Handler handler, {
    required int index,
    required String text,
  }) {
    return _ListInsertOperation(
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
        'type': type.toString(),
        'id': id,
        'index': index,
        'text': text,
      };

  static _ListInsertOperation fromPayload(dynamic payload) =>
      _ListInsertOperation(
        id: payload['id'],
        type: payload['type'],
        index: payload['index'],
        text: payload['text'],
      );
}

class _ListDeleteOperation extends Operation {
  const _ListDeleteOperation({
    required this.index,
    required this.count,
    required super.id,
    required super.type,
  });

  factory _ListDeleteOperation.fromHandler(
    Handler handler, {
    required int index,
    required int count,
  }) {
    return _ListDeleteOperation(
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
        'type': type.toString(),
        'id': id,
        'index': index,
        'count': count,
      };

  static _ListDeleteOperation fromPayload(dynamic payload) =>
      _ListDeleteOperation(
        id: payload['id'],
        type: payload['type'],
        index: payload['index'],
        count: payload['count'],
      );
}
