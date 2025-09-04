/// Base exception for all CRDT-related errors.
class CrdtException implements Exception {
  /// Constructor
  const CrdtException(this.message);

  /// The message of the exception
  final String message;

  @override
  String toString() => 'CrdtException: $message';
}

/// Thrown when a change cannot be applied because its causal dependencies
/// (previous changes) are not yet present in the document's history.
class CausallyNotReadyException extends CrdtException {
  /// Constructor
  const CausallyNotReadyException(super.message);
}

/// Thrown when a cycle is detected in the dependency graph of changes,
/// which would violate the causal ordering of operations.
class ChangesCycleException extends CrdtException {
  /// Constructor
  const ChangesCycleException(super.message);
}

/// Thrown when attempting to add a node (e.g., a change or an element)
/// to a data structure that already contains a node with the same identifier.
class DuplicateNodeException extends CrdtException {
  /// Constructor
  const DuplicateNodeException(super.message);
}

/// Thrown when a change references a dependency that does not exist
/// in the document's history (the DAG).
class MissingDependencyException extends CrdtException {
  /// Constructor
  const MissingDependencyException(super.message);
}

/// Thrown when attempting to register a handler that already exists.
class HandlerAlreadyRegisteredException extends CrdtException {
  /// Constructor
  const HandlerAlreadyRegisteredException(super.message);
}
