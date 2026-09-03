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
/// writes while offline pays nothing for a push that is not happening — and so
/// [pending] can be written down and handed back through [restore], which is
/// what carries at-least-once across a restart.
class RelayPendingQueue {
  final List<Change> _pending = [];

  /// How many changes at the head of the queue are in flight
  int _inFlight = 0;

  /// Number of changes waiting for an ack (in flight included)
  int get length => _pending.length;

  /// Whether the queue is empty
  bool get isEmpty => _pending.isEmpty;

  /// Whether a push is in flight
  bool get hasInFlight => _inFlight > 0;

  /// The changes waiting for an ack, oldest first.
  ///
  /// Persist these to carry delivery across a restart: without them, a change
  /// written while offline is restored into the document but never reaches the
  /// relay, because it comes back as an imported change rather than a local
  /// one.
  List<Change> get pending => List.unmodifiable(_pending);

  /// Appends [change] to the queue.
  void add(Change change) {
    _pending.add(change);
  }

  /// Puts [changes] back at the head of the queue, skipping the ones already
  /// queued.
  ///
  /// For a queue seeded from what a previous session wrote down. At the head
  /// because they are older than anything this session produced, and the queue
  /// is pushed in order.
  void restore(Iterable<Change> changes) {
    assert(!hasInFlight, 'a push is already in flight');
    final queued = {for (final change in _pending) change.id};
    _pending.insertAll(
      0,
      changes.where((change) => !queued.contains(change.id)),
    );
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
