import 'package:crdt_lf/crdt_lf.dart';

/// Manages transactional batching of notifications and local changes emission.
///
/// The owner provides callbacks to emit local [Change]s and updates.
///
/// While a transaction is active, emissions are deferred and flushed
/// upon commit of the outermost transaction.
class TransactionManager {
  /// Constructor
  TransactionManager({
    required this.emitLocalChange,
    required this.emitUpdate,
  });

  /// Callback used to emit a locally generated change when not in a transaction
  /// or when flushing at commit time.
  final void Function(Change change) emitLocalChange;

  /// Callback used to notify listeners about document updates when not in a
  /// transaction or when flushing at commit time.
  final void Function() emitUpdate;

  /// The depth of the transaction stack.
  int _depth = 0;

  /// The list of pending local changes.
  final List<Change> _pendingLocalChanges = <Change>[];

  /// Whether there is a pending update.
  bool _hasPendingUpdate = false;

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

    // Flush pending local changes
    if (_pendingLocalChanges.isNotEmpty) {
      for (final change in List<Change>.from(_pendingLocalChanges)) {
        emitLocalChange(change);
      }
      _pendingLocalChanges.clear();
    }

    // Flush a single updates notification if any are pending
    if (_hasPendingUpdate) {
      _hasPendingUpdate = false;
      emitUpdate();
    }
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

  /// Handles a locally generated change: if a transaction is active, the
  /// change is queued and an update is marked as pending; otherwise the change
  /// and the update are emitted immediately.
  void handleLocalChange(Change change) {
    if (isInTransaction) {
      _pendingLocalChanges.add(change);
      _hasPendingUpdate = true;
      return;
    }

    emitLocalChange(change);
    emitUpdate();
  }

  /// Requests an update notification. If a transaction is active, the update
  /// is marked as pending; otherwise it is emitted immediately.
  void requestUpdate() {
    if (isInTransaction) {
      _hasPendingUpdate = true;
      return;
    }
    emitUpdate();
  }
}
