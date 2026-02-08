import 'package:crdt_lf/src/handler/handler.dart';

const _insert = 'insert';
const _delete = 'delete';
const _update = 'update';
const _availableOperations = {_insert, _delete, _update};

/// Available operation on data for CRDT.
///
/// Also holds the binary kind constants used in the operation envelope (u8).
class OperationType {
  OperationType._({
    required this.handler,
    required this.type,
  });

  /// Binary kind value for insert (u8 in the operation envelope).
  static const int kindInsert = 0;

  /// Binary kind value for delete (u8 in the operation envelope).
  static const int kindDelete = 1;

  /// Binary kind value for update (u8 in the operation envelope).
  static const int kindUpdate = 2;

  /// Binary kind value for this operation type (0=insert, 1=delete, 2=update).
  int get kind {
    if (type == _insert) {
      return kindInsert;
    }
    if (type == _delete) {
      return kindDelete;
    }
    if (type == _update) {
      return kindUpdate;
    }
    throw FormatException('Unknown operation type: $type');
  }

  /// Returns the type name string for a binary [kind] value.
  static String typeNameFromKind(int kind) {
    if (kind == kindInsert) {
      return _insert;
    }
    if (kind == kindDelete) {
      return _delete;
    }
    if (kind == kindUpdate) {
      return _update;
    }
    throw FormatException('Unknown operation kind: $kind');
  }

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
