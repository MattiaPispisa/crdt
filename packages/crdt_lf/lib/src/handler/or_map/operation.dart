part of 'handler.dart';

class _ORMapOperationFactory<K, V> {
  _ORMapOperationFactory(this.handler);
  final Handler<dynamic> handler;

  Operation? fromPayload(Map<String, dynamic> payload) {
    if (Operation.handlerIdFrom(payload: payload) != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _ORMapPutOperation<K, V>.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _ORMapRemoveOperation<K, V>.fromPayload(payload);
    }

    return null;
  }
}

/// Put operation for OR-Map
/// It adds a new unique tag for the provided key-value pair.
class _ORMapPutOperation<K, V> extends Operation {
  const _ORMapPutOperation({
    required this.key,
    required this.value,
    required this.tag,
    required super.id,
    required super.type,
  });

  factory _ORMapPutOperation.fromHandler(
    Handler<dynamic> handler, {
    required K key,
    required V value,
    required ORHandlerTag tag,
  }) {
    return _ORMapPutOperation<K, V>(
      id: handler.id,
      type: OperationType.insert(handler),
      key: key,
      value: value,
      tag: tag,
    );
  }

  factory _ORMapPutOperation.fromPayload(Map<String, dynamic> payload) {
    return _ORMapPutOperation<K, V>(
      id: payload['id'] as String,
      type: OperationType.fromPayload(payload['type'] as String),
      key: payload['key'] as K,
      value: payload['value'] as V,
      tag: ORHandlerTag.parse(payload['tag'] as String),
    );
  }

  final K key;
  final V value;
  final ORHandlerTag tag;

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'key': key,
      'value': value,
      'tag': tag.toString(),
    };
  }
}

/// Remove operation for OR-Map
/// It tombstones the provided tags that were observed for a key.
class _ORMapRemoveOperation<K, V> extends Operation {
  const _ORMapRemoveOperation({
    required this.key,
    required this.tags,
    required this.removeAll,
    required super.id,
    required super.type,
  });

  factory _ORMapRemoveOperation.fromHandler(
    Handler<dynamic> handler, {
    required K key,
    required Set<ORHandlerTag> tags,
  }) {
    return _ORMapRemoveOperation<K, V>(
      id: handler.id,
      type: OperationType.delete(handler),
      key: key,
      tags: Set.from(tags),
      removeAll: tags.isEmpty,
    );
  }

  factory _ORMapRemoveOperation.fromPayload(Map<String, dynamic> payload) {
    final raw = payload['tags'] as List<dynamic>? ?? const <dynamic>[];
    return _ORMapRemoveOperation<K, V>(
      id: payload['id'] as String,
      type: OperationType.fromPayload(payload['type'] as String),
      key: payload['key'] as K,
      tags: raw.map((e) => ORHandlerTag.parse(e as String)).toSet(),
      removeAll: (payload['removeAll'] as bool?) ?? false,
    );
  }

  final K key;
  final Set<ORHandlerTag> tags;
  final bool removeAll;

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'key': key,
      'tags': tags.map((t) => t.toString()).toList(),
      'removeAll': removeAll,
    };
  }
}
