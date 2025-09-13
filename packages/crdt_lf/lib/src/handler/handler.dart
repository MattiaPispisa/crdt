import 'package:crdt_lf/crdt_lf.dart';

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
  final CRDTDocument doc;

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
}
