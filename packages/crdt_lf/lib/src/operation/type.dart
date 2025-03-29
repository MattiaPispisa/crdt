import '../handler/handler.dart';

/// Available operation on data for CRDT
class OperationType {
  const OperationType._({
    required this.handler,
    required this.type,
  });

  /// Insert operation
  factory OperationType.insert(Handler handler) {
    return OperationType._(
      handler: handler.runtimeType.toString(),
      type: 'insert',
    );
  }

  /// Delete operation
  factory OperationType.delete(Handler handler) {
    return OperationType._(
      handler: handler.runtimeType.toString(),
      type: 'delete',
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
}
