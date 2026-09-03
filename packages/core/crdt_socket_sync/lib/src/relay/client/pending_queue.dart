import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';

/// Queue of local [Change]s not yet acknowledged by the relay.
///
/// Implements at-least-once delivery: a change leaves the queue only when the
/// relay acknowledges it. At most one push is in flight at a time; if the
/// connection drops, [resetInFlight] returns the in-flight window to the
/// pending state so the changes are re-pushed after the next welcome
/// (re-delivery is safe: peers de-duplicate imported changes).
///
/// Changes are held as they are and encoded at push time, so a client that
/// writes while offline pays nothing for a push that is not happening.
///
/// Surviving a restart is not this queue's job: the document is what an app
/// writes down, and `RelaySyncManager.onWelcome` queues everything the relay
/// turns out not to hold.
class RelayPendingQueue {
  final List<Change> _pending = [];

  /// The ids in [_pending], so [add] skips a duplicate without a scan.
  final Set<OperationId> _queued = <OperationId>{};

  /// How many changes at the head of the queue are in flight
  int _inFlight = 0;

  /// Number of changes waiting for an ack (in flight included)
  int get length => _pending.length;

  /// Whether the queue is empty
  bool get isEmpty => _pending.isEmpty;

  /// Whether a push is in flight
  bool get hasInFlight => _inFlight > 0;

  /// The changes waiting for an ack, oldest first.
  List<Change> get pending => List.unmodifiable(_pending);

  /// Appends [change] to the queue, unless it is already waiting.
  ///
  /// The welcome reconciliation queues what the relay does not hold, and a
  /// change written while that was in flight is already here.
  void add(Change change) {
    if (!_queued.add(change.id)) {
      return;
    }
    _pending.add(change);
  }

  /// Marks every pending change as in flight and returns them.
  ///
  /// Must not be called while a push is in flight ([hasInFlight]).
  List<Change> takeInFlight() {
    assert(!hasInFlight, 'a push is already in flight');
    _inFlight = _pending.length;
    return List.unmodifiable(_pending);
  }

  /// Drops the acknowledged head of the queue.
  ///
  /// [count] is the number of changes the relay persisted; it is bounded by
  /// the in-flight window so a misbehaving ack cannot drop changes that were
  /// never pushed.
  void ack(int count) {
    final acked = min(min(count, _inFlight), _pending.length);
    for (var i = 0; i < acked; i++) {
      _queued.remove(_pending[i].id);
    }
    _pending.removeRange(0, acked);
    _inFlight = 0;
  }

  /// Returns the in-flight window to the pending state.
  ///
  /// Called when the connection drops with a push in flight: the outcome of
  /// the push is unknown, so the changes stay queued for re-delivery.
  void resetInFlight() {
    _inFlight = 0;
  }
}
