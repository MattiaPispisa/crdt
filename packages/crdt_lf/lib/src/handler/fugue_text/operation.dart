part of 'handler.dart';

/// Factory for Fugue operations
class _FugueTextOperationFactory {
  /// Constructor that initializes the factory
  _FugueTextOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler<dynamic> handler;

  /// Creates an operation from a payload
  Operation? fromPayload(Map<String, dynamic> payload) {
    if (Operation.handlerIdFrom(payload: payload) != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _FugueTextInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _FugueTextDeleteOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.update(handler).toPayload()) {
      return _FugueTextUpdateOperation.fromPayload(payload);
    }

    return null;
  }
}

/// Batch insert operation for the Fugue algorithm
class _FugueTextInsertOperation extends Operation {
  /// Constructor that initializes a batch insert operation
  _FugueTextInsertOperation({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
    required super.id,
    required super.type,
  });

  /// Creates a batch insert operation from a payload
  factory _FugueTextInsertOperation.fromPayload(
    Map<String, dynamic> payload,
  ) {
    return _FugueTextInsertOperation(
      id: payload['id'] as String,
      type: OperationType.fromPayload(payload['type'] as String),
      leftOrigin: FugueElementID.fromJson(
        payload['leftOrigin'] as Map<String, dynamic>,
      ),
      rightOrigin: FugueElementID.fromJson(
        payload['rightOrigin'] as Map<String, dynamic>,
      ),
      items: (payload['items'] as List)
          .map(
            (e) => _FugueInsertItem.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  /// Factory to create a batch insert operation from a handler
  factory _FugueTextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<_FugueInsertItem> items,
  }) {
    return _FugueTextInsertOperation(
      id: handler.id,
      type: OperationType.insert(handler),
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
    );
  }

  /// ID of the left origin node for the batch
  final FugueElementID leftOrigin;

  /// ID of the right origin node for the batch
  final FugueElementID rightOrigin;

  /// Items to insert sequentially (first uses [leftOrigin], others chain)
  final List<_FugueInsertItem> items;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'leftOrigin': leftOrigin.toJson(),
        'rightOrigin': rightOrigin.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
      };
}

/// A single item of a batch insert
class _FugueInsertItem {
  _FugueInsertItem({
    required this.id,
    required this.text,
  });

  factory _FugueInsertItem.fromJson(Map<String, dynamic> json) {
    return _FugueInsertItem(
      id: FugueElementID.fromJson(json['id'] as Map<String, dynamic>),
      text: json['text'] as String,
    );
  }

  final FugueElementID id;
  final String text;

  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        'text': text,
      };
}

/// Delete operation for the Fugue algorithm
class _FugueTextDeleteOperation extends Operation {
  /// Constructor that initializes a delete operation
  _FugueTextDeleteOperation({
    required this.nodeID,
    required super.id,
    required super.type,
  });

  /// Creates a delete operation from a payload
  factory _FugueTextDeleteOperation.fromPayload(Map<String, dynamic> payload) =>
      _FugueTextDeleteOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        nodeID: FugueElementID.fromJson(
          payload['nodeID'] as Map<String, dynamic>,
        ),
      );

  /// Factory to create a delete operation from a handler
  factory _FugueTextDeleteOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID nodeID,
  }) {
    return _FugueTextDeleteOperation(
      id: handler.id,
      type: OperationType.delete(handler),
      nodeID: nodeID,
    );
  }

  /// ID of the node to delete
  final FugueElementID nodeID;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'nodeID': nodeID.toJson(),
      };
}

/// Update operation for the Fugue algorithm
class _FugueTextUpdateOperation extends Operation {
  /// Constructor that initializes an update operation
  _FugueTextUpdateOperation({
    required this.nodeID,
    required this.newNodeID,
    required this.text,
    required super.id,
    required super.type,
  });

  /// Creates an update operation from a payload
  factory _FugueTextUpdateOperation.fromPayload(Map<String, dynamic> payload) =>
      _FugueTextUpdateOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        nodeID:
            FugueElementID.fromJson(payload['nodeID'] as Map<String, dynamic>),
        newNodeID: FugueElementID.fromJson(
          payload['newNodeID'] as Map<String, dynamic>,
        ),
        text: payload['text'] as String,
      );

  /// Factory to create an update operation from a handler
  factory _FugueTextUpdateOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID nodeID,
    required FugueElementID newNodeID,
    required String text,
  }) {
    return _FugueTextUpdateOperation(
      id: handler.id,
      type: OperationType.update(handler),
      nodeID: nodeID,
      newNodeID: newNodeID,
      text: text,
    );
  }

  /// ID of the node to update
  final FugueElementID nodeID;

  /// ID of the new node
  final FugueElementID newNodeID;

  /// Text to update
  final String text;

  @override
  Map<String, dynamic> toPayload() => {
        ...super.toPayload(),
        'nodeID': nodeID.toJson(),
        'newNodeID': newNodeID.toJson(),
        'text': text,
      };
}
