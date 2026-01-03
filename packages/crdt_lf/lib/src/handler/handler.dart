import 'package:crdt_lf/crdt_lf.dart';

/// A factory function that creates an operation from a payload
typedef OperationFactory = Operation? Function(
  Map<String, dynamic> payload,
);

/// Abstract class for CRDT handlers
///
/// A handler is a component that manages the state of a specific
/// data structure in the CRDT system.
abstract class Handler<T>
    with DocumentConsumer, SnapshotProvider, CacheableStateProvider<T> {
  /// Creates a new handler for the given document
  Handler(this.doc) {
    doc.registerHandler(this);
  }

  /// The document that owns this handler
  final BaseCRDTDocument doc;

  /// The factory function that creates an operation from a payload
  OperationFactory get operationFactory;

  /// During transaction consecutive operations can be compounded.
  ///
  /// By default, no compaction occurs and operations are returned as-is.
  ///
  /// Override this method to implement a compact algorithm.
  ///
  /// [accumulator] is the previous operation
  /// [current] is the current operation
  ///
  /// If [current] can be compounded with [accumulator],
  /// return the **new compounded** operation (union of the two).
  ///
  /// Otherwise, return `null`.
  Operation? compound(Operation accumulator, Operation current) => null;

  /// Returns the operations required by this consumer to compute its state.
  ///
  /// The operations are returned in the order they were applied.
  List<Operation> operations() {
    final changes = doc
        .exportChanges(
          fromVersionVector: snapshotVersionVector(),
        )
        .sorted(inplace: true);

    final operations = <Operation>[];
    for (final change in changes) {
      final operation = operationFactory(change.payload);
      if (operation != null) {
        operations.add(operation);
      }
    }

    return operations;
  }
}
