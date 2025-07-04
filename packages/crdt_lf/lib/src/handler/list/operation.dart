part of 'handler.dart';

class _ListOperationFactory<T> {
  _ListOperationFactory(this.handler);
  final Handler<dynamic> handler;

  Operation? fromPayload(Map<String, dynamic> payload) {
    if (payload['id'] != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _ListInsertOperation.fromPayload<T>(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _ListDeleteOperation.fromPayload<T>(payload);
    } else if (payload['type'] == OperationType.update(handler).toPayload()) {
      return _ListUpdateOperation.fromPayload<T>(payload);
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
    Handler<dynamic> handler, {
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
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'value': value,
      };

  static _ListInsertOperation<T> fromPayload<T>(Map<String, dynamic> payload) =>
      _ListInsertOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        value: payload['value'] as T,
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
    Handler<dynamic> handler, {
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
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'count': count,
      };

  static _ListDeleteOperation<T> fromPayload<T>(Map<String, dynamic> payload) =>
      _ListDeleteOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        count: payload['count'] as int,
      );
}

class _ListUpdateOperation<T> extends Operation {
  const _ListUpdateOperation({
    required this.index,
    required this.value,
    required super.id,
    required super.type,
  });

  factory _ListUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required int index,
    required T value,
  }) {
    return _ListUpdateOperation(
      id: handler.id,
      type: OperationType.update(handler),
      index: index,
      value: value,
    );
  }

  final int index;
  final T value;

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'index': index,
        'value': value,
      };

  static _ListUpdateOperation<T> fromPayload<T>(Map<String, dynamic> payload) =>
      _ListUpdateOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        value: payload['value'] as T,
      );
}
