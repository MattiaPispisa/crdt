import 'package:crdt_lf/src/handler/handler.dart';

const _insert = 'insert';
const _delete = 'delete';
const _update = 'update';
const _availableOperations = {_insert, _delete, _update};

/// Available operation on data for CRDT
class OperationType {
  OperationType._({
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
    final index = payload.indexOf(':');

    if (index == -1) {
      throw FormatException('Invalid payload: $payload');
    }

    final handler = payload.substring(0, index);
    final type = payload.substring(index + 1);

    if (handler.isEmpty ||
        type.isEmpty ||
        !_availableOperations.contains(type)) {
      throw FormatException('Invalid payload: $payload');
    }

    return OperationType._(
      handler: handler,
      type: type,
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

  late final int _hashCode = Object.hash(handler, type);

  /// Returns a hash code for this [OperationType]
  @override
  int get hashCode => _hashCode;

  /// Returns a payload for this [OperationType]
  String toPayload() {
    return '$handler:$type';
  }
}
