import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';

/// A delta that can be folded together with the delta that follows it.
///
/// [HandlerDelta.delta] is always one of these: a change that fuses several
/// operations carries the composition of their deltas.
abstract interface class ComposableDelta<D> {
  /// Whether this delta moves nothing.
  bool get isEmpty;

  /// The delta that has the same effect as this one followed by [next].
  ///
  /// [next] is read in the coordinates of the state **after** this delta.
  D compose(D next);
}

/// One event in the delta stream of a handler.
///
/// A consumer seeds its projection from a [HandlerReset], then keeps it up to
/// date from the [HandlerDelta] events that follow. It never has to read the
/// handler's value again.
sealed class HandlerUpdate<D> {
  /// Creates an event carrying the sequence number [seq].
  const HandlerUpdate({required this.seq});

  /// The sequence number of this event for the handler that emitted it.
  ///
  /// It only grows, and never restarts. It is what reconciles a
  /// [HandlerReset] with the events after it: the reset's value is read
  /// separately, and [seq] says which point of the stream it reflects.
  final int seq;
}

/// The observable state of the handler moved by [delta].
final class HandlerDelta<D> extends HandlerUpdate<D> {
  /// Creates the event that reports [delta].
  const HandlerDelta({
    required this.delta,
    required this.changeId,
    required this.author,
    required this.local,
    required super.seq,
    this.origin,
  });

  /// How the state moved.
  ///
  /// Its coordinates are those of the state **before** this event.
  final D delta;

  /// The id of the change that carried the move; one event per change.
  final OperationId changeId;

  /// The peer that wrote the change.
  final PeerId author;

  /// Whether this peer authored the change.
  ///
  /// **Not an echo flag.** It answers "did this peer write it", which is wider
  /// than "did I just write it" in two ways: two consumers on one document read
  /// `true` for each other's work, and a change this peer wrote in an earlier
  /// session reads `true` when a persistence adapter loads it back. A consumer
  /// that skipped on this would drop content it never applied. Use [origin].
  ///
  /// What it is good for is provenance: showing who edited, or telling an edit
  /// of this peer from one that came over the network.
  final bool local;

  /// What the call that produced this change was tagged with; `null` when it
  /// was not tagged.
  ///
  /// Any object, compared by identity. It never travels, so it costs nothing on
  /// the wire.
  ///
  /// A consumer that writes tags its writes and skips what comes back — a write
  /// publishes before it has finished its own bookkeeping, so applying the echo
  /// would apply the edit twice.
  ///
  /// ```dart
  /// document.runInTransaction(() => text.insert(0, 'a'), origin: this);
  /// // in the listener:
  /// if (identical(update.origin, this)) return;
  /// ```
  ///
  /// A [HandlerReset] carries none.
  final Object? origin;

  @override
  String toString() => 'HandlerDelta(seq: $seq, changeId: $changeId, '
      'author: $author, local: $local, origin: $origin, delta: $delta)';
}

/// The observable state is no longer reachable by delta: read it again.
///
/// Ordinary traffic, not an error. On a reset a consumer calls the handler's
/// `readSynced()`, adopts the value, and drops every [HandlerDelta] whose
/// [HandlerUpdate.seq] the returned one already covers.
final class HandlerReset<D> extends HandlerUpdate<D> {
  /// Creates the event that asks for a fresh read.
  const HandlerReset({required this.cause, required super.seq});

  /// Why the deltas stopped describing the state.
  final ResetCause cause;

  @override
  String toString() => 'HandlerReset(seq: $seq, cause: $cause)';
}

/// Why a [HandlerReset] was emitted.
enum ResetCause {
  /// The first event of a subscription. Every subscription starts here, so the
  /// reset path runs on the first frame rather than only on a rare event.
  initial,

  /// A snapshot replaced the base the replay starts from.
  snapshotImport,

  /// A snapshot was merged into the base the replay starts from.
  snapshotMerge,

  /// The cached state was dropped, so there is nothing left to move.
  ///
  /// A handler that reads in replay order drops it whenever a change arrives
  /// that sorts before what it holds — two peers typing at once. The next read
  /// replays the history.
  cacheDropped,

  /// A change could not be folded into the state: its operation failed to
  /// decode, threw, or was refused.
  ///
  /// A handler that merely has no incremental path reports [cacheDropped].
  applyFailed,

  /// Queued changes were folded without anyone collecting their deltas: a read
  /// reached the queue before the eager drain did.
  ///
  /// The state is right; only the deltas describing the last step are gone.
  deltasMissed,
}

/// A value together with the point of the delta stream it reflects.
///
/// Returned by a handler's `readSynced()`. One operation, not two: an event
/// landing between a read and a `seq` query would be applied twice.
final class DeltaSyncPoint<V> {
  /// Creates a sync point.
  const DeltaSyncPoint({required this.value, required this.seq});

  /// The value of the handler at the moment of the read.
  final V value;

  /// The sequence number of the last event this value already includes.
  ///
  /// Discard every [HandlerDelta] whose [HandlerUpdate.seq] is less than or
  /// equal to this.
  final int seq;

  @override
  String toString() => 'DeltaSyncPoint(seq: $seq, value: $value)';
}
