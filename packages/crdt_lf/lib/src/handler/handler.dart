part of '../document/document.dart';

/// A factory function that creates an operation from bytes.
///
/// Returns `null` when the envelope belongs to another handler — a different
/// instance id or a different type tag. That is a normal answer, and the
/// caller skips the change.
///
/// Throws [UnknownOperationKindException] when the envelope *is* addressed to
/// this handler but carries a kind this build cannot decode. That change comes
/// from a newer peer, and skipping it would leave two peers with different
/// states and the same version vector.
typedef OperationFactory = Operation? Function(
  Uint8List operationBytes,
);

/// Abstract class for CRDT handlers
///
/// A handler is a component that manages the state of a specific
/// data structure in the CRDT system.
///
/// ## Extension points
///
/// Most of the members below this class are for **writing** a handler, not for
/// using one. Using a handler means calling the API of the concrete class
/// (`value`, `insert`, `set`, …); nothing here has to be called by hand.
///
/// A custom handler overrides:
///
/// - [id] and [operationFactory] — required: how the handler is addressed and
///   how its operations are decoded.
/// - [getSnapshotState] — required: the state as bytes, seeded back through
///   [lastSnapshot].
/// - [handlerType] — for a handler that must survive dart2js minification.
/// - [incrementCachedState] — to advance the cached state by one operation
///   instead of replaying the history.
/// - [stateIsOrderIndependent] — only when the state is the same
///   whatever the order causally ready operations arrive in.
/// - [compound] — to collapse consecutive operations inside a transaction.
///
/// And it reads its state through [cachedState] / [updateCachedState],
/// replaying [operations] when there is nothing cached.
///
/// The hooks the framework calls on a handler are private to this library, so
/// they never show up on a handler you hold.
abstract class Handler<T>
    with DocumentConsumer, SnapshotProvider, CacheableStateProvider<T> {
  /// Creates a new handler for the given document.
  ///
  /// [handlerType] optionally overrides the type tag
  /// (see [Handler.handlerType]);
  /// pass a stable constant for generic handlers
  /// that must work in a minified build.
  Handler(this.doc, {String? handlerType}) : _handlerType = handlerType {
    doc.registerHandler(this);
  }

  /// The document that owns this handler
  final BaseCRDTDocument doc;

  final String? _handlerType;

  /// The factory function that creates an operation from a payload.
  ///
  /// See [OperationFactory] for what `null` means and when the decode throws.
  OperationFactory get operationFactory;

  /// Stable identifier of this handler's **type**.
  ///
  /// Used as the type tag in operation envelopes, in the snapshot handler
  /// manifest and in [HandlerRef]s, and as the key under which a
  /// [HandlerFactory] is registered (see [BaseCRDTDocument.registerFactory]).
  /// The same value is produced on every peer so changes route to the matching
  /// handler and nested handlers can be reconstructed remotely.
  ///
  /// Defaults to `runtimeType.toString()`, which is convenient but **not
  /// stable under dart2js minification**. Custom handlers
  /// that must work in a minified build (or persist/sync across builds) should
  /// override it with their own constant, or pass one to the constructor.
  String get handlerType => _handlerType ?? runtimeType.toString();

  /// Cached insert type instances for this handler, used in operations.
  late final OperationType insertType = OperationType.insert(this);

  /// Cached delete type instances for this handler, used in operations.
  late final OperationType deleteType = OperationType.delete(this);

  /// Cached update type instances for this handler, used in operations.
  late final OperationType updateType = OperationType.update(this);

  /// Cached move type instances for this handler, used in operations.
  late final OperationType moveType = OperationType.move(this);

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

  @override
  Operation? _operationFromChange(Change change) =>
      operationFactory(change.payloadBytes());

  /// Returns the [Operation]s required by this consumer to compute its state.
  ///
  /// The [Operation]s are returned in the order they were applied.
  List<Operation> operations() {
    final changes = doc
        .changesForHandler(
          id,
          fromVersionVector: _snapshotVersionVector(),
        )
        .sorted(inplace: true);

    // The list is sorted, so its last entry is the newest change the caller is
    // about to fold in. See [CacheableStateProvider._noteReplayBoundary].
    _noteReplayBoundary(changes.isEmpty ? null : changes.last);

    final operations = <Operation>[];
    for (final change in changes) {
      final operation = operationFactory(change.payloadBytes());
      if (operation != null) {
        operations.add(operation);
      }
    }

    return operations;
  }
}
