import 'package:crdt_lf/src/handler/handler.dart';

const _insert = 'insert';
const _delete = 'delete';
const _update = 'update';
const _availableOperations = {_insert, _delete, _update};

/// Available operation on data for CRDT
class OperationType {
  const OperationType._({
    required this.handler,
    required this.type,
  });

  /// Insert operation
  factory OperationType.insert(Handler<dynamic> handler) {
    return OperationType._(
      handler: handler.runtimeType.toString(),
      type: _insert,
    );
  }

  /// Delete operation
  factory OperationType.delete(Handler<dynamic> handler) {
    return OperationType._(
      handler: handler.runtimeType.toString(),
      type: _delete,
    );
  }

  /// Update operation
  factory OperationType.update(Handler<dynamic> handler) {
    return OperationType._(
      handler: handler.runtimeType.toString(),
      type: _update,
    );
  }

  /// Factory to create an operation type from a payload
  factory OperationType.fromPayload(String payload) {
    final parts = payload.split(':');

    if (parts.length != 2 ||
        parts[0].isEmpty ||
        parts[1].isEmpty ||
        !_availableOperations.contains(parts[1])) {
      throw FormatException('Invalid payload: $payload');
    }

    return OperationType._(
      handler: parts[0],
      type: parts[1],
    );
  }

  /// Handler type
  final String handler;

  /// Operation type
  final String type;

  /// Compares two [OperationType]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OperationType &&
        other.handler == handler &&
        other.type == type;
  }

  /// Returns a hash code for this [OperationType]
  @override
  int get hashCode => Object.hash(handler, type);

  /// Returns a payload for this [OperationType]
  String toPayload() {
    return '$handler:$type';
  }
}
