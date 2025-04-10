part of 'handler.dart';

/// Factory for Fugue operations
class _FugueTextOperationFactory {
  /// Constructor that initializes the factory
  _FugueTextOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler handler;

  /// Creates an operation from a payload
  Operation? fromPayload(dynamic payload) {
    if (payload['id'] != handler.id) {
      return null;
    }

    if (payload['type'] == OperationType.insert(handler).toPayload()) {
      return _FugueTextInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toPayload()) {
      return _FugueTextDeleteOperation.fromPayload(payload);
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

  /// Factory to create an insert operation from a handler
  factory _FugueTextInsertOperation.fromHandler(
    Handler handler, {
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
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'newNodeID': newNodeID.toJson(),
        'text': text,
        'leftOrigin': leftOrigin.toJson(),
        'rightOrigin': rightOrigin.toJson(),
      };

  /// Creates an insert operation from a payload
  static _FugueTextInsertOperation fromPayload(dynamic payload) =>
      _FugueTextInsertOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        newNodeID: FugueElementID.fromJson(payload['newNodeID']),
        text: payload['text'],
        leftOrigin: FugueElementID.fromJson(payload['leftOrigin']),
        rightOrigin: FugueElementID.fromJson(payload['rightOrigin']),
      );
}

/// Delete operation for the Fugue algorithm
class _FugueTextDeleteOperation extends Operation {
  /// Constructor that initializes a delete operation
  _FugueTextDeleteOperation({
    required this.nodeID,
    required super.id,
    required super.type,
  });

  /// Factory to create a delete operation from a handler
  factory _FugueTextDeleteOperation.fromHandler(
    Handler handler, {
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
  dynamic toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'nodeID': nodeID.toJson(),
      };

  /// Creates a delete operation from a payload
  static _FugueTextDeleteOperation fromPayload(dynamic payload) =>
      _FugueTextDeleteOperation(
        id: payload['id'],
        type: OperationType.fromPayload(payload['type']),
        nodeID: FugueElementID.fromJson(payload['nodeID']),
      );
}
