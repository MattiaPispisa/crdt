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

/// Thrown when a change addressed to this handler carries an operation kind
/// this build cannot decode.
///
/// It means the change was written by a newer peer. Dropping it silently would
/// let two peers hold different states while agreeing on the same version
/// vector, so it is raised instead. Catch it to tell the user that this peer
/// needs an upgrade.
///
/// A change meant for another handler is not this: that one is still answered
/// with `null` and skipped.
class UnknownOperationKindException extends CrdtException {
  /// Constructor
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

/// Thrown when attempting to register a handler that already exists.
class HandlerAlreadyRegisteredException extends CrdtException {
  /// Constructor
  const HandlerAlreadyRegisteredException(super.message);
}

/// Thrown when attempting to execute a method on a read-only document.
class ReadOnlyDocumentException extends CrdtException {
  /// Constructor
  const ReadOnlyDocumentException(String methodInvoked)
      : super('Impossible to execute $methodInvoked. '
            'The document is in time travel mode (Read-Only).');
}

/// Thrown when attempting to execute a method on a disposed document.
class DocumentDisposedException extends CrdtException {
  /// Constructor
  const DocumentDisposedException(String methodInvoked)
      : super('Cannot execute $methodInvoked.'
            ' The document has been disposed.');
}
