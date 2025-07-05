part of 'handler.dart';

class _MapOperationFactory<T> {
  _MapOperationFactory(this.handler);
  final Handler<dynamic> handler;

  Operation? fromPayload(Map<String, dynamic> payload) {
    if (payload['id'] != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _MapInsertOperation<T>.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _MapDeleteOperation<T>.fromPayload(payload);
    } else if (payload['type'] == OperationType.update(handler).toPayload()) {
      return _MapUpdateOperation<T>.fromPayload(payload);
    }

    return null;
  }
}

class _MapInsertOperation<T> extends Operation {
  const _MapInsertOperation({
    required this.key,
    required this.value,
    required super.id,
    required super.type,
  });

  factory _MapInsertOperation.fromPayload(
    Map<String, dynamic> payload,
  ) =>
      _MapInsertOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        key: payload['key'] as String,
        value: payload['value'] as T,
      );

  factory _MapInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required String key,
    required T value,
  }) {
    return _MapInsertOperation<T>(
      id: handler.id,
      type: OperationType.insert(handler),
      key: key,
      value: value,
    );
  }

  final String key;
  final T value;

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'key': key,
        'value': value,
      };
}

class _MapDeleteOperation<T> extends Operation {
  const _MapDeleteOperation({
    required this.key,
    required super.id,
    required super.type,
  });

  factory _MapDeleteOperation.fromPayload(
    Map<String, dynamic> payload,
  ) =>
      _MapDeleteOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        key: payload['key'] as String,
      );

  factory _MapDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required String key,
  }) {
    return _MapDeleteOperation<T>(
      id: handler.id,
      type: OperationType.delete(handler),
      key: key,
    );
  }

  final String key;

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'key': key,
      };
}

class _MapUpdateOperation<T> extends Operation {
  const _MapUpdateOperation({
    required this.key,
    required this.value,
    required super.id,
    required super.type,
  });

  factory _MapUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required String key,
    required T value,
  }) {
    return _MapUpdateOperation(
      id: handler.id,
      type: OperationType.update(handler),
      key: key,
      value: value,
    );
  }

  factory _MapUpdateOperation.fromPayload(Map<String, dynamic> payload) =>
      _MapUpdateOperation<T>(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        key: payload['key'] as String,
        value: payload['value'] as T,
      );

  final String key;
  final T value;

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'key': key,
        'value': value,
      };
}
