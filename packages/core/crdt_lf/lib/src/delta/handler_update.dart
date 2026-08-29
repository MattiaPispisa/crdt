import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';

/// A delta that can be folded together with the delta that follows it.
///
/// [HandlerDelta.delta] is always one of these: a change that fuses several
/// operations carries the composition of their deltas.
abstract interface class ComposableDelta<D> {
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
  /// It only ever grows, and never restarts.
  ///
  /// It is what reconciles a [HandlerReset] with the events that follow it:
  /// the value a reset asks for is read separately, and [seq] says which point
  /// of the stream that value reflects.
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
  });

  /// How the state moved.
  ///
  /// Its coordinates are those of the state **before** this event.
  final D delta;

  /// The id of the change that carried the move.
  ///
  /// One event covers exactly one change. A transaction whose operations do
  /// not compound produces several changes, and therefore several events.
  final OperationId changeId;

  /// The peer that wrote the change.
  final PeerId author;

  /// Whether this document wrote the change itself.
  final bool local;

  @override
  String toString() => 'HandlerDelta(seq: $seq, changeId: $changeId, '
      'author: $author, local: $local, delta: $delta)';
}

/// The observable state is no longer reachable by delta: read it again.
///
/// A reset is not an error. It is the honest answer when the base the replay
/// starts from has been replaced, or when the handler dropped the cached state
/// the deltas were describing.
///
/// On a reset a consumer calls the handler's `readSynced()`, adopts the value
/// it returns, remembers its sequence number, and discards any [HandlerDelta]
/// whose [HandlerUpdate.seq] is less than or equal to it.
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
  /// The first event of a subscription.
  ///
  /// Every subscription starts here, so a consumer exercises its reset path on
  /// the first frame instead of months later in production.
  initial,

  /// A snapshot replaced the base the replay starts from.
  snapshotImport,

  /// A snapshot was merged into the base the replay starts from.
  snapshotMerge,

  /// The cached state was dropped, so there is nothing left to move.
  ///
  /// A handler that reads its state in replay order
  /// drops the cache whenever a change arrives that sorts before what it
  /// already holds — two peers typing at the same time. The next read replays
  /// the history, which is the cost that read already had.
  cacheDropped,

  /// A change could not be folded into the state.
  ///
  /// Its operation could not be decoded, or it threw while being applied, or
  /// the document refused the change outright. A handler that simply has no
  /// incremental path for an operation is not a failure and reports
  /// [cacheDropped] instead.
  applyFailed,

  /// Queued changes were folded into the state without anyone collecting
  /// their deltas.
  ///
  /// A safety net: it means a read reached the queue before the eager drain
  /// did. The state is correct; only the deltas that described the last step
  /// are gone.
  deltasMissed,
}

/// A value together with the point of the delta stream it reflects.
///
/// Returned by a handler's `readSynced()`. Reading the value and learning
/// which events it already includes is one operation, so a consumer cannot
/// apply a delta twice.
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
