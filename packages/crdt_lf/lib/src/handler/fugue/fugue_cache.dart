import 'package:crdt_lf/crdt_lf.dart';

/// Reusable plumbing shared by every Fugue-backed handler, independent of how
/// the handler lays out its state or navigates positions.
///
/// It provides the two concerns that are orthogonal to the concrete data
/// structure:
/// - **per-peer element-id allocation** ([nextCounter]), lazily seeded from
///   the ids the handler already knows about, and
/// - **the cache lifecycle**: [cachedOrComputedState] (compute on miss) and an
///   incremental [incrementCachedState] that mutates the cached state in place
///   and invalidates it on failure.
///
/// A host mixes it in and provides three hooks — [knownElementIds],
/// [computeState] and [applyOperation] — none of which assume anything about
/// how positions or the public value are derived. This is what lets a future
/// handler whose visible order is decoupled from the tree (e.g. a movable
/// list) reuse the counter and the cache without inheriting the ordered
/// sequence semantics of `FugueSequenceHandler`.
mixin FugueCache<S> on Handler<S> {
  int? _counter;

  // --- Hooks implemented by the host ---

  /// All element ids already known to this handler, from its snapshot and its
  /// operation history. Used to seed [nextCounter] above any counter this peer
  /// has already produced.
  Iterable<FugueElementID> knownElementIds();

  /// Computes the state from scratch (snapshot seed + full history replay).
  S computeState();

  /// Applies a single [operation] to [state] in place, leaving the state's
  /// derived projections consistent (e.g. marked stale).
  void applyOperation(S state, Operation operation);

  // --- Per-peer element-id counter ---

  /// Returns the next unique element counter for this peer.
  ///
  /// Seeded lazily on first use from [knownElementIds].
  int nextCounter() {
    if (_counter == null) {
      var max = -1;
      for (final id in knownElementIds()) {
        if (!id.isNull && id.replicaID == doc.peerId) {
          final c = id.counter!;
          if (c > max) max = c;
        }
      }
      _counter = max + 1;
    }
    final result = _counter!;
    _counter = result + 1;
    return result;
  }

  // --- Cache lifecycle ---

  /// Returns the cached state if still valid, otherwise computes it via
  /// [computeState] and caches it.
  S cachedOrComputedState() {
    final cached = cachedState;
    if (cached != null) {
      return cached;
    }

    final state = computeState();
    updateCachedState(state);
    return state;
  }

  @override
  S? incrementCachedState({
    required Operation operation,
    required S state,
  }) {
    // The state is mutated in place; on failure the (possibly half-mutated)
    // cache is invalidated by returning null.
    try {
      applyOperation(state, operation);
      return state;
    } catch (_) {
      return null;
    }
  }
}
