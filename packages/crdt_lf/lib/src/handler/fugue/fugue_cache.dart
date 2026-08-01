import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/element_id_floor.dart';

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

  /// The highest element counter each peer is known to have used, seeded from
  /// the snapshot. See [ElementIdFloor].
  final Map<PeerId, int> _elementIdFloor = <PeerId, int>{};

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
  /// Seeded lazily on first use from [knownElementIds] and from the floor the
  /// snapshot carries, so a counter is never handed out twice.
  int nextCounter() {
    _counter ??= (_maxCountersByPeer()[doc.peerId] ?? -1) + 1;
    final result = _counter!;
    _counter = result + 1;
    return result;
  }

  /// Records that every peer in [floor] has already used counters up to the
  /// given value, and lifts an already-seeded counter above its own entry.
  ///
  /// Called by the snapshot decoders.
  void seedElementIdFloor(Map<PeerId, int> floor) {
    ElementIdFloor.mergeInto(_elementIdFloor, floor);

    final own = _elementIdFloor[doc.peerId];
    final counter = _counter;
    if (own != null && counter != null && counter <= own) {
      _counter = own + 1;
    }
  }

  /// The floor to store in the next snapshot: the counters this handler knows
  /// about, plus the ones inherited from the snapshot it was seeded with.
  ///
  /// The inherited part is what keeps the counters of pruned tombstones alive
  /// across successive snapshots.
  Map<PeerId, int> elementIdFloorForSnapshot() => _maxCountersByPeer();

  /// The highest counter per peer over [knownElementIds] merged with
  /// [_elementIdFloor].
  Map<PeerId, int> _maxCountersByPeer() {
    final result = <PeerId, int>{};
    // Walking the ids first matters: decoding the snapshot is what seeds
    // [_elementIdFloor], and it happens inside [knownElementIds].
    for (final id in knownElementIds()) {
      if (id.isNull) {
        continue;
      }
      final counter = id.counter!;
      final current = result[id.replicaID];
      if (current == null || counter > current) {
        result[id.replicaID] = counter;
      }
    }
    ElementIdFloor.mergeInto(result, _elementIdFloor);
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
