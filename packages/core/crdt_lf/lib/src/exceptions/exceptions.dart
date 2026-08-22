/// {@template crdt_exception}
/// Base exception for all CRDT-related errors.
/// {@endtemplate}
class CrdtException implements Exception {
  /// {@macro crdt_exception}
  const CrdtException(this.message);

  /// The message of the exception
  final String message;

  @override
  String toString() => 'CrdtException: $message';
}

/// {@template causally_not_ready_exception}
/// Thrown when a change cannot be applied because its causal dependencies
/// (previous changes) are not yet present in the document's history.
/// {@endtemplate}
class CausallyNotReadyException extends CrdtException {
  /// {@macro causally_not_ready_exception}
  const CausallyNotReadyException(super.message);
}

/// {@template changes_cycle_exception}
/// Thrown when a cycle is detected in the dependency graph of changes,
/// which would violate the causal ordering of operations.
/// {@endtemplate}
class ChangesCycleException extends CrdtException {
  /// {@macro changes_cycle_exception}
  const ChangesCycleException(super.message);
}

/// {@template duplicate_node_exception}
/// Thrown when attempting to add a node (e.g., a change or an element)
/// to a data structure that already contains a node with the same identifier.
/// {@endtemplate}
class DuplicateNodeException extends CrdtException {
  /// {@macro duplicate_node_exception}
  const DuplicateNodeException(super.message);
}

/// {@template missing_dependency_exception}
/// Thrown when a change references a dependency that does not exist
/// in the document's history (the DAG).
/// {@endtemplate}
class MissingDependencyException extends CrdtException {
  /// {@macro missing_dependency_exception}
  const MissingDependencyException(super.message);
}

/// {@template unknown_operation_kind_exception}
/// Thrown when a change **addressed to this handler** carries an operation kind
/// this build cannot decode.
/// {@endtemplate}
class UnknownOperationKindException extends CrdtException {
  /// {@macro unknown_operation_kind_exception}
  const UnknownOperationKindException({
    required this.handlerType,
    required this.handlerId,
    required this.kind,
  }) : super('Handler $handlerType($handlerId) cannot decode operation '
            'kind $kind. The change comes from a newer peer.');

  /// The handler type tag carried by the envelope.
  final String handlerType;

  /// The handler instance id carried by the envelope.
  final String handlerId;

  /// The kind byte this build does not know how to decode.
  final int kind;
}

/// {@template handler_already_registered_exception}
/// Thrown when attempting to register a handler that already exists.
/// {@endtemplate}
class HandlerAlreadyRegisteredException extends CrdtException {
  /// {@macro handler_already_registered_exception}
  const HandlerAlreadyRegisteredException(super.message);
}

/// {@template read_only_document_exception}
/// Thrown when attempting to execute a method on a read-only document.
/// {@endtemplate}
class ReadOnlyDocumentException extends CrdtException {
  /// {@macro read_only_document_exception}
  const ReadOnlyDocumentException(String methodInvoked)
      : super('Impossible to execute $methodInvoked. '
            'The document is in time travel mode (Read-Only).');
}

/// {@template document_disposed_exception}
/// Thrown when attempting to execute a method on a disposed document.
/// {@endtemplate}
class DocumentDisposedException extends CrdtException {
  /// {@macro document_disposed_exception}
  const DocumentDisposedException(String methodInvoked)
      : super('Cannot execute $methodInvoked.'
            ' The document has been disposed.');
}
