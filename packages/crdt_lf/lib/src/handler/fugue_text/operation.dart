part of 'handler.dart';

/// Factory for Fugue operations
class _FugueOperationFactory {
  /// Constructor that initializes the factory
  _FugueOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler handler;

  /// Creates an operation from a payload
  Operation? fromPayload(dynamic payload) {
    if (payload['id'] != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _FugueInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _FugueDeleteOperation.fromPayload(payload);
    }

    return null;
  }
}

/// Insert operation for the Fugue algorithm
class _FugueInsertOperation extends Operation {
  /// Constructor that initializes an insert operation
  _FugueInsertOperation({
    required this.newNodeID,
    required this.text,
    required this.leftOrigin,
    required this.rightOrigin,
    required super.id,
    required super.type,
  });

  /// Factory to create an insert operation from a handler
  factory _FugueInsertOperation.fromHandler(
    Handler handler, {
    required FugueElementID newNodeID,
    required String text,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    return _FugueInsertOperation(
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
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'newNodeID': newNodeID.toJson(),
        'text': text,
        'leftOrigin': leftOrigin.toJson(),
        'rightOrigin': rightOrigin.toJson(),
      };

  /// Creates an insert operation from a payload
  static _FugueInsertOperation fromPayload(dynamic payload) =>
      _FugueInsertOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        newNodeID: FugueElementID.fromJson(payload['newNodeID']),
        text: payload['text'],
        leftOrigin: FugueElementID.fromJson(payload['leftOrigin']),
        rightOrigin: FugueElementID.fromJson(payload['rightOrigin']),
      );
}

/// Delete operation for the Fugue algorithm
class _FugueDeleteOperation extends Operation {
  /// Constructor that initializes a delete operation
  _FugueDeleteOperation({
    required this.nodeID,
    required super.id,
    required super.type,
  });

  /// Factory to create a delete operation from a handler
  factory _FugueDeleteOperation.fromHandler(
    Handler handler, {
    required FugueElementID nodeID,
  }) {
    return _FugueDeleteOperation(
      id: handler.id,
      type: OperationType.delete(handler),
      nodeID: nodeID,
    );
  }

  /// ID of the node to delete
  final FugueElementID nodeID;

  @override
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'nodeID': nodeID.toJson(),
      };

  /// Creates a delete operation from a payload
  static _FugueDeleteOperation fromPayload(dynamic payload) =>
      _FugueDeleteOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        nodeID: FugueElementID.fromJson(payload['nodeID']),
      );
}
