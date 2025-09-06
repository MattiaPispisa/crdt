part of 'handler.dart';

class _TextOperationFactory {
  _TextOperationFactory(this.handler);
  final Handler<dynamic> handler;

  Operation? fromPayload(Map<String, dynamic> payload) {
    if (Operation.handlerIdFrom(payload: payload) != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _TextInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _TextDeleteOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.update(handler).toPayload()) {
      return _TextUpdateOperation.fromPayload(payload);
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

  factory _TextInsertOperation.fromPayload(Map<String, dynamic> payload) =>
      _TextInsertOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        text: payload['text'] as String,
      );

  factory _TextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
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

  factory _TextDeleteOperation.fromPayload(Map<String, dynamic> payload) =>
      _TextDeleteOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        count: payload['count'] as int,
      );

  factory _TextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
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
      type: OperationType.update(handler),
      index: index,
      text: text,
    );
  }

  factory _TextUpdateOperation.fromPayload(Map<String, dynamic> payload) =>
      _TextUpdateOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        index: payload['index'] as int,
        text: payload['text'] as String,
      );

  final int index;
  final String text;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'index': index,
        'text': text,
      };
}
