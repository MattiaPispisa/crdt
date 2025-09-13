import 'package:crdt_lf/src/operation/type.dart';

/// Abstract class for operations
abstract class Operation {
  /// Constructor that initializes an operation
  const Operation({
    required this.type,
    required this.id,
  });

  /// The type of the operation
  final OperationType type;

  /// The ID of the handler that owns the operation
  final String id;

  /// The [Operation.id] of the operation from a [payload]
  static String handlerIdFrom({
    required Map<String, dynamic> payload,
  }) {
    return payload['id'] as String;
  }

  /// Converts the operation to a payload
  Map<String, dynamic> toPayload() {
    return {
      'id': id,
      'type': type.toPayload(),
    };
  }
}
