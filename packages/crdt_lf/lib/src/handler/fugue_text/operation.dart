import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';

import 'element_id.dart';

/// Insert operation for the Fugue algorithm
class FugueInsertOperation extends Operation {
  /// Constructor that initializes an insert operation
  FugueInsertOperation({
    required this.newNodeID,
    required this.text,
    required this.leftOrigin,
    required this.rightOrigin,
    required super.id,
    required super.type,
  });

  /// Factory to create an insert operation from a handler
  factory FugueInsertOperation.fromHandler(
    Handler handler, {
    required FugueElementID newNodeID,
    required String text,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    return FugueInsertOperation(
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
        'type': type.toString(),
        'id': id,
        'newNodeID': newNodeID.toJson(),
        'text': text,
        'leftOrigin': leftOrigin.toJson(),
        'rightOrigin': rightOrigin.toJson(),
      };

  /// Creates an insert operation from a payload
  static FugueInsertOperation fromPayload(dynamic payload) =>
      FugueInsertOperation(
        id: payload['id'],
        type: payload['type'],
        newNodeID: FugueElementID.fromJson(payload['newNodeID']),
        text: payload['text'],
        leftOrigin: FugueElementID.fromJson(payload['leftOrigin']),
        rightOrigin: FugueElementID.fromJson(payload['rightOrigin']),
      );
}

/// Delete operation for the Fugue algorithm
class FugueDeleteOperation extends Operation {
  /// Constructor that initializes a delete operation
  FugueDeleteOperation({
    required this.nodeID,
    required super.id,
    required super.type,
  });

  /// Factory to create a delete operation from a handler
  factory FugueDeleteOperation.fromHandler(
    Handler handler, {
    required FugueElementID nodeID,
  }) {
    return FugueDeleteOperation(
      id: handler.id,
      type: OperationType.delete(handler),
      nodeID: nodeID,
    );
  }

  /// ID of the node to delete
  final FugueElementID nodeID;

  @override
  dynamic toPayload() => {
        'type': type.toString(),
        'id': id,
        'nodeID': nodeID.toJson(),
      };

  /// Creates a delete operation from a payload
  static FugueDeleteOperation fromPayload(dynamic payload) =>
      FugueDeleteOperation(
        id: payload['id'],
        type: payload['type'],
        nodeID: FugueElementID.fromJson(payload['nodeID']),
      );
}

/// Factory for Fugue operations
class FugueOperationFactory {
  /// Constructor that initializes the factory
  FugueOperationFactory(this.handler);

  /// The handler associated with this factory
  final Handler handler;

  /// Creates an operation from a payload
  Operation? fromPayload(dynamic payload) {
    if (payload['type'] == OperationType.insert(handler).toString()) {
      return FugueInsertOperation.fromPayload(payload);
    } else if (payload['type'] == OperationType.delete(handler).toString()) {
      return FugueDeleteOperation.fromPayload(payload);
    }

    return null;
  }
}
