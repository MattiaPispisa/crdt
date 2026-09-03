import 'package:crdt_lf/crdt_lf.dart';

/// Manages transactional batching of notifications and local changes emission.
///
/// The owner provides callbacks to emit local [Change]s and updates.
///
/// While a transaction is active, emissions are deferred and flushed
/// upon commit of the outermost transaction.
///
/// ```dart
/// final manager = TransactionManager(
///   flushWork: _transactionFlushWork,
/// );
///
/// manager.run(() {
///   listHandler
///     ..insert(0, 'Hello')
///     ..insert(1, 'World')
/// });
///
/// ```
class TransactionManager {
  /// Constructor
  TransactionManager({
    required this.flushWork,
    this.onFlushed,
  });

  /// Callback used to flush the work done during the transaction:
  ///
  /// - `operations`: the operations applied during the transaction
  /// - `createdChanges`: the changes the document wrote itself
  /// - `ingestedChanges`: the changes the document took in from elsewhere
  /// - `otherPendingUpdates`: whether there are other pending updates
  ///
  /// The two lists of changes are kept apart because they answer different
  /// questions: what to send to peers, and what to write down. A change is in
  /// exactly one of them.
  final void Function(
    List<Operation> operations,
    List<Change> createdChanges,
    List<Change> ingestedChanges,
    // ignore: avoid_positional_boolean_parameters the only boolean positional parameter
    bool otherPendingUpdates,
  ) flushWork;

  /// Called once the flush is over and this manager holds nothing anymore.
  ///
  /// This is the moment the document is settled and idle, so it is the only
  /// safe place to hand events to code that may write back: called any earlier,
  /// a write would re-enter [_flushWork] while it still holds the work it is
  /// flushing, and apply it twice.
  ///
  /// The document hands out its delta events from here. What waits for this
  /// moment, and why, is written down on the outbox those events wait in.
  final void Function()? onFlushed;

  /// The depth of the transaction stack.
  int _depth = 0;

  /// The list of pending local changes.
  final List<Operation> _pendingOperations = <Operation>[];

  /// The changes the document wrote itself during the current transaction.
  final List<Change> _pendingCreatedChanges = <Change>[];

  /// The changes the document took in during the current transaction.
  final List<Change> _pendingIngestedChanges = <Change>[];

  /// Whether an update has been requested.
  bool _hasRequestedUpdate = false;

  /// Whether a transaction is currently active.
  bool get isInTransaction => _depth > 0;

  /// Begins a new transaction (supports nesting).
  void begin() {
    _depth++;
  }

  /// Commits the current transaction. When the outermost transaction is
  /// committed, pending updates and local changes are flushed.
  void commit() {
    if (_depth == 0) {
      throw StateError('No active transaction to commit');
    }

    _depth--;
    if (_depth > 0) {
      return;
    }

    _flushWork();
  }

  /// Runs [action] within a transaction, committing at the end.
  T run<T>(T Function() action) {
    begin();
    try {
      return action();
    } finally {
      commit();
    }
  }

  /// Handles a locally generated operation.
  ///
  /// If a transaction is active, the operation is queued
  /// and an update is marked as pending; otherwise the operation
  /// is emitted immediately.
  void handleOperation(Operation operation) {
    if (isInTransaction) {
      _pendingOperations.add(operation);
      return;
    }

    _pendingOperations.add(operation);
    _flushWork();
  }

  /// Handles changes the document has just applied.
  ///
  /// [created] tells the two queues apart: `true` when the document wrote the
  /// changes, `false` when it took them in from elsewhere.
  ///
  /// If a transaction is active, the changes are queued
  /// and an update is marked as pending; otherwise changes
  /// are emitted immediately.
  void handleAppliedChanges(
    List<Change> changes, {
    required bool created,
  }) {
    (created ? _pendingCreatedChanges : _pendingIngestedChanges)
        .addAll(changes);

    if (isInTransaction) {
      return;
    }

    _flushWork();
  }

  /// Requests an update notification.
  ///
  /// If a transaction is active, the update
  /// is marked as pending; otherwise it is emitted immediately.
  void requestUpdate() {
    if (isInTransaction) {
      _hasRequestedUpdate = true;
      return;
    }

    _hasRequestedUpdate = true;
    _flushWork();
  }

  void _flushWork() {
    flushWork(
      List.of(_pendingOperations),
      List.of(_pendingCreatedChanges),
      List.of(_pendingIngestedChanges),
      _hasRequestedUpdate,
    );
    _pendingOperations.clear();
    _pendingCreatedChanges.clear();
    _pendingIngestedChanges.clear();
    _hasRequestedUpdate = false;
    onFlushed?.call();
  }
}
