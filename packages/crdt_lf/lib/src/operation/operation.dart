import 'package:crdt_lf/src/operation/type.dart';

abstract class Operation {
  const Operation({
    required this.type,
    required this.id,
  });

  final OperationType type;
  final String id;

  /// Converts the operation to a payload
  dynamic toPayload();
}
