part of 'handler.dart';

class _ORSetOperationFactory<T> {
  _ORSetOperationFactory(this.handler);
  final Handler<dynamic> handler;

  Operation? fromPayload(Map<String, dynamic> payload) {
    if (Operation.handlerIdFrom(payload: payload) != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _ORSetAddOperation<T>.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _ORSetRemoveOperation<T>.fromPayload(payload);
    }

    return null;
  }
}

/// Add operation for OR-Set
/// It adds a new unique tag for the provided value.
class _ORSetAddOperation<T> extends Operation {
  const _ORSetAddOperation({
    required this.value,
    required this.tag,
    required super.id,
    required super.type,
  });

  factory _ORSetAddOperation.fromHandler(
    Handler<dynamic> handler, {
    required T value,
    required String tag,
  }) {
    return _ORSetAddOperation<T>(
      id: handler.id,
      type: OperationType.insert(handler),
      value: value,
      tag: tag,
    );
  }

  factory _ORSetAddOperation.fromPayload(Map<String, dynamic> payload) {
    return _ORSetAddOperation<T>(
      id: payload['id'] as String,
      type: OperationType.fromPayload(payload['type'] as String),
      value: payload['value'] as T,
      tag: payload['tag'] as String,
    );
  }

  final T value;
  final String tag;

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'value': value,
      'tag': tag,
    };
  }
}

/// Remove operation for OR-Set
/// It tombstones the provided tags that were observed for a value.
class _ORSetRemoveOperation<T> extends Operation {
  const _ORSetRemoveOperation({
    required this.value,
    required this.tags,
    required this.removeAll,
    required super.id,
    required super.type,
  });

  factory _ORSetRemoveOperation.fromHandler(
    Handler<dynamic> handler, {
    required T value,
    required Set<String> tags,
  }) {
    return _ORSetRemoveOperation<T>(
      id: handler.id,
      type: OperationType.delete(handler),
      value: value,
      tags: Set.from(tags),
      removeAll: tags.isEmpty,
    );
  }

  factory _ORSetRemoveOperation.fromPayload(Map<String, dynamic> payload) {
    final raw = payload['tags'] as List<dynamic>? ?? const <dynamic>[];
    return _ORSetRemoveOperation<T>(
      id: payload['id'] as String,
      type: OperationType.fromPayload(payload['type'] as String),
      value: payload['value'] as T,
      tags: raw.map((e) => e as String).toSet(),
      removeAll: (payload['removeAll'] as bool?) ?? false,
    );
  }

  final T value;
  final Set<String> tags;
  final bool removeAll;

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'value': value,
      'tags': tags.toList(),
      'removeAll': removeAll,
    };
  }
}
