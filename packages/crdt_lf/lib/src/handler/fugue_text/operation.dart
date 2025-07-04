part of 'handler.dart';

/// Factory for Fugue operations
class _FugueTextOperationFactory {
  /// Constructor that initializes the factory
  _FugueTextOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler<dynamic> handler;

  /// Creates an operation from a payload
  Operation? fromPayload(Map<String, dynamic> payload) {
    if (payload['id'] != handler.id) {
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

/// Insert operation for the Fugue algorithm
class _FugueTextInsertOperation extends Operation {
  /// Constructor that initializes an insert operation
  _FugueTextInsertOperation({
    required this.newNodeID,
    required this.text,
    required this.leftOrigin,
    required this.rightOrigin,
    required super.id,
    required super.type,
  });

  /// Creates an insert operation from a payload
  factory _FugueTextInsertOperation.fromPayload(Map<String, dynamic> payload) =>
      _FugueTextInsertOperation(
        id: payload['id'] as String,
        type: OperationType.fromPayload(payload['type'] as String),
        newNodeID: FugueElementID.fromJson(
          payload['newNodeID'] as Map<String, dynamic>,
        ),
        text: payload['text'] as String,
        leftOrigin: FugueElementID.fromJson(
          payload['leftOrigin'] as Map<String, dynamic>,
        ),
        rightOrigin: FugueElementID.fromJson(
          payload['rightOrigin'] as Map<String, dynamic>,
        ),
      );

  /// Factory to create an insert operation from a handler
  factory _FugueTextInsertOperation.fromHandler(
    Handler<dynamic> handler, {
    required FugueElementID newNodeID,
    required String text,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    return _FugueTextInsertOperation(
      id: handler.id,
      type: OperationType.insert(handler),
      newNodeID: newNodeID,
      text: text,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
    );
  }

  /// ID of the new node
  final FugueElementID newNodeID;

  /// Text to insert
  final String text;

  /// ID of the left origin node
  final FugueElementID leftOrigin;

  /// ID of the right origin node
  final FugueElementID rightOrigin;

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'newNodeID': newNodeID.toJson(),
        'text': text,
        'leftOrigin': leftOrigin.toJson(),
        'rightOrigin': rightOrigin.toJson(),
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
        'type': type.toPayload(),
        'id': id,
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
        'type': type.toPayload(),
        'id': id,
        'nodeID': nodeID.toJson(),
        'newNodeID': newNodeID.toJson(),
        'text': text,
      };
}
