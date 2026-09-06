import 'package:crdt_lf/crdt_lf.dart';

/// The work a committed transaction collected.
///
/// `events` holds one entry per move of the durable state, in the order the
/// moves happened.
typedef TransactionWork = ({
  /// The operations applied during the transaction.
  List<Operation> operations,

  /// The events the document collected during the transaction, in order.
  List<CRDTDocumentEvent> events,

  /// Whether there are other pending updates.
  bool otherPendingUpdates,
});

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

  /// Callback used to flush the work done during the transaction.
  ///
  /// The lists it gets are copies: this manager clears its own right after
  /// the call, so the callback may keep them.
  final void Function(TransactionWork work) flushWork;

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

  /// The events the current transaction collected, in the order the document
  /// moved.
  ///
  /// One list for every kind of event, not one per kind: a snapshot taken
  /// after a change was applied has to reach a listener after that change, and
  /// two queues drained one after the other cannot say which came first.
  final List<CRDTDocumentEvent> _pendingEvents = <CRDTDocumentEvent>[];

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

  /// Handles a batch of changes the document has just applied.
  ///
  /// The batch arrives ready to publish: where it came from and who asked for
  /// it are read where the work happened, not here. A nested call restores the
  /// origin it interrupted before this manager commits, so reading it at the
  /// flush would report the wrong one.
  ///
  /// If a transaction is active, the batch is queued and flushed, in order, at
  /// the commit that ends it; otherwise it is emitted immediately.
  void handleAppliedChanges(DocumentChangesApplied event) {
    _pendingEvents.add(event);

    if (isInTransaction) {
      return;
    }

    _flushWork();
  }

  /// Queues [event] when a transaction is open, and says whether it did.
  ///
  /// Snapshots and prunes come this way. They move the store the moment they
  /// are called, while the changes of the same transaction are only published
  /// at the commit — so publishing them straight away would report a prune
  /// before the change it removed.
  ///
  /// `false` means no transaction is open and the caller publishes the event
  /// itself: outside a transaction there is nothing to order it against.
  bool queueEvent(CRDTDocumentEvent event) {
    if (!isInTransaction) {
      return false;
    }
    _pendingEvents.add(event);
    return true;
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
      (
        operations: List.of(_pendingOperations),
        events: List.of(_pendingEvents),
        otherPendingUpdates: _hasRequestedUpdate,
      ),
    );
    _pendingOperations.clear();
    _pendingEvents.clear();
    _hasRequestedUpdate = false;
    onFlushed?.call();
  }
}
