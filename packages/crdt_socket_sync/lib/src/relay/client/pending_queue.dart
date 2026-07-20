import 'dart:math';

/// Queue of local change blobs not yet acknowledged by the relay.
///
/// Implements at-least-once delivery: a blob leaves the queue only when the
/// relay acknowledges it. At most one push is in flight at a time; if the
/// connection drops, [resetInFlight] returns the in-flight window to the
/// pending state so the blobs are re-pushed after the next welcome
/// (re-delivery is safe: peers de-duplicate imported changes).
class RelayPendingQueue {
  final List<String> _pending = [];

  /// How many blobs at the head of the queue are in flight
  int _inFlight = 0;

  /// Number of blobs waiting for an ack (in flight included)
  int get length => _pending.length;

  /// Whether the queue is empty
  bool get isEmpty => _pending.isEmpty;

  /// Whether a push is in flight
  bool get hasInFlight => _inFlight > 0;

  /// Appends [blob] to the queue.
  void add(String blob) {
    _pending.add(blob);
  }

  /// Marks every pending blob as in flight and returns them.
  ///
  /// Must not be called while a push is in flight ([hasInFlight]).
  List<String> takeInFlight() {
    assert(!hasInFlight, 'a push is already in flight');
    _inFlight = _pending.length;
    return List.unmodifiable(_pending);
  }

  /// Drops the acknowledged head of the queue.
  ///
  /// [count] is the number of blobs the relay persisted; it is bounded by
  /// the in-flight window so a misbehaving ack cannot drop blobs that were
  /// never pushed.
  void ack(int count) {
    final acked = min(min(count, _inFlight), _pending.length);
    _pending.removeRange(0, acked);
    _inFlight = 0;
  }

  /// Returns the in-flight window to the pending state.
  ///
  /// Called when the connection drops with a push in flight: the outcome of
  /// the push is unknown, so the blobs stay queued for re-delivery.
  void resetInFlight() {
    _inFlight = 0;
  }
}
