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

  /// The ID of the operation
  final String id;

  /// Converts the operation to a payload
  Map<String, dynamic> toPayload();
}
