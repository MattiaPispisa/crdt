part of 'handler.dart';

class _ListOperationFactory<T> {
  final Handler handler;

  _ListOperationFactory(this.handler);

  Operation? fromPayload(dynamic payload) {
    if (payload['id'] != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _ListInsertOperation.fromPayload<T>(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _ListDeleteOperation.fromPayload<T>(payload);
    }

    return null;
  }
}

class _ListInsertOperation<T> extends Operation {
  const _ListInsertOperation({
    required this.index,
    required this.value,
    required super.id,
    required super.type,
  });

  factory _ListInsertOperation.fromHandler(
    Handler handler, {
    required int index,
    required T value,
  }) {
    return _ListInsertOperation(
      id: handler.id,
      type: OperationType.insert(handler),
      index: index,
      value: value,
    );
  }

  final int index;
  final T value;

  @override
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'value': value,
      };

  static _ListInsertOperation<T> fromPayload<T>(dynamic payload) =>
      _ListInsertOperation<T>(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        index: payload['index'],
        value: payload['value'],
      );
}

class _ListDeleteOperation<T> extends Operation {
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
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'count': count,
      };

  static _ListDeleteOperation<T> fromPayload<T>(dynamic payload) =>
      _ListDeleteOperation<T>(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        index: payload['index'],
        count: payload['count'],
      );
}
