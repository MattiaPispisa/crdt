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
  });

  /// Callback used to flush the work done during the transaction:
  ///
  /// - `operations`: the operations applied during the transaction
  /// - `changes`: the changes applied during the transaction
  /// - `otherPendingUpdates`: whether there are other pending updates
  final void Function(
    List<Operation> operations,
    List<Change> changes,
    // ignore: avoid_positional_boolean_parameters the only boolean positional parameter
    bool otherPendingUpdates,
  ) flushWork;

  /// The depth of the transaction stack.
  int _depth = 0;

  /// The list of pending local changes.
  final List<Operation> _pendingOperations = <Operation>[];

  /// The list of changes applied during the current transaction.
  final List<Change> _pendingChanges = <Change>[];

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

  /// Handles locally generated changes.
  ///
  /// If a transaction is active, the changes are queued
  /// and an update is marked as pending; otherwise changes
  /// are emitted immediately.
  void handleAppliedChanges(List<Change> changes) {
    if (isInTransaction) {
      _pendingChanges.addAll(changes);
      return;
    }

    _pendingChanges.addAll(changes);
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
      List.of(_pendingChanges),
      _hasRequestedUpdate,
    );
    _pendingOperations.clear();
    _pendingChanges.clear();
    _hasRequestedUpdate = false;
  }
}
