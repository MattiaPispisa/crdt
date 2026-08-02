part of 'document.dart';

/// A consumer that can consume a CRDTDocument
mixin DocumentConsumer {
  /// The document that `this` can consume
  late final BaseCRDTDocument _document;

  /// The unique identifier for `this` consumer
  String get id;
}

/// Per-consumer state cache that avoids recomputing the consumer's state
/// from the full history on every read.
///
/// Three update paths:
/// - **incremental**: when a single [Operation] is applied, the cache is
///   patched via [incrementCachedState]. Hosts that can cheaply apply an
///   operation to their state override it; returning `null` means "can't
///   (or won't) update incrementally" and falls back to invalidation.
/// - **queued**: an imported change is parked and folded in on the next read
///   instead of dropping the cache. Allowed when the change is newer than
///   everything already folded in, or when the host declares
///   [stateIsOrderIndependent].
/// - **full recompute**: [cachedState] returns `null` whenever the cached
///   version no longer matches the document's current version (e.g. after
///   import, snapshot merge or prune). The host recomputes the state from
///   scratch and pushes it back via [updateCachedState].
///
/// [T] is the host's own internal representation. It has no required
/// relationship with `handler.value` or [SnapshotProvider.getSnapshotState]
/// — pick whatever shape makes recomputation cheap.
///
/// Set [useIncrementalCacheUpdate] to false to ignore [incrementCachedState]
mixin CacheableStateProvider<T> on DocumentConsumer {
  @override
  String get id;

  /// Document version the cached state is pinned to (`null` when no
  /// state is cached). The cache is valid only while this set equals
  /// `_document.version`.
  Set<OperationId>? _cachedVersion;

  /// The most recently cached state, or `null` if no state is cached.
  T? _cachedState;

  /// If `false`, every applied operation invalidates the cache instead of
  /// invoking [incrementCachedState]. Hosts that have no cheap incremental
  /// path may set this to `false` to skip the hook entirely; the default
  /// `true` lets each operation try the incremental path first.
  bool useIncrementalCacheUpdate = true;

  /// Changes already applied to the document but not yet folded into
  /// [_cachedState].
  List<Change>? _pendingRemoteChanges;

  /// The newest change, in replay order, already folded into [_cachedState] or
  /// waiting in [_pendingRemoteChanges].
  ///
  /// `null` while [_replayBoundaryMatchesState] is `true` means the state was
  /// built from no change at all (an empty history, or a snapshot seed only),
  /// so every change is newer than it.
  Change? _replayBoundary;

  /// Whether [_replayBoundary] still describes what [_cachedState] holds.
  ///
  /// It does not between registering a local operation and committing it: the
  /// operation is already folded into the state, but the change that carries it
  /// — and its clock — is only created on commit, so the state holds something
  /// with no place in the replay order. The rule that compares against the
  /// boundary stays closed for that window; [_noteReplayBoundary] reopens it.
  bool _replayBoundaryMatchesState = false;

  /// How many changes may wait in [_pendingRemoteChanges] before the cache is
  /// dropped instead.
  ///
  /// Draining costs one decode plus one apply per queued change, a full
  /// recompute costs one per change in the history. Past this many the
  /// recompute is the cheaper option, and the bound also caps the memory a
  /// host nobody reads can hold on to.
  static const int _maxPendingRemoteChanges = 256;

  /// Whether the state is the same **whatever the order** causally ready
  /// operations are applied in.
  ///
  /// When it is, a remote change can be folded into the cached state in arrival
  /// order, instead of in the sorted order [Handler.operations] replays. The
  /// state has to be commutative under causal delivery: every ordering of the
  /// same causally ready changes must give the same state.
  ///
  /// A host that resolves conflicts by replay order (e.g. last-write-wins on
  /// the position of an operation in the history) must leave it `false`,
  /// otherwise two peers that receive the same changes in a different order
  /// diverge. Such a host still takes the incremental path for a change that is
  /// newer than everything already folded in.
  bool get stateIsOrderIndependent => false;

  /// The operation carried by [change], or `null` when it cannot be decoded.
  ///
  /// Used to drain [_pendingRemoteChanges]; `null` makes the framework fall
  /// back to a full recompute. [Handler] implements it with its
  /// [Handler.operationFactory].
  Operation? _operationFromChange(Change change) => null;

  /// Records the newest change, in replay order, folded into the cached state.
  ///
  /// Called by [Handler.operations] with the last change of the set a recompute
  /// replays, and by the document when a local change is created — a local
  /// change carries a clock newer than every change already applied, so it is
  /// the new boundary whatever came before it.
  ///
  /// Pass `null` for "nothing was replayed": every change is then newer.
  void _noteReplayBoundary(Change? change) {
    _replayBoundary = change;
    _replayBoundaryMatchesState = true;
  }

  /// Whether folding [changes] in order on top of the current state gives the
  /// same result as replaying the whole history sorted.
  ///
  /// True when each change is newer than the boundary and than the one before
  /// it. A fold that only ever receives the new maximum agrees with the sorted
  /// replay whatever the host does with each operation — which is why this
  /// works for hosts that are not commutative.
  bool _extendsReplayOrder(List<Change> changes) {
    if (!_replayBoundaryMatchesState) {
      return false;
    }

    var previous = _replayBoundary;
    for (final change in changes) {
      if (previous != null && compareChangeOrder(change, previous) <= 0) {
        return false;
      }
      previous = change;
    }
    return true;
  }

  /// Parks [changes] until the next read, all of them or none.
  ///
  /// Returns `false` when the caller has to [invalidateCache] instead: the
  /// host holds no state to advance, the queue would grow past
  /// [_maxPendingRemoteChanges], or the changes neither commute with the state
  /// nor extend the replay order.
  bool _queueRemoteChanges(List<Change> changes) {
    if (changes.isEmpty || !useIncrementalCacheUpdate) {
      return false;
    }

    if (!stateIsOrderIndependent && !_extendsReplayOrder(changes)) {
      return false;
    }

    // The raw field, not [cachedState]: this runs after the document version
    // has already moved past these changes, so the getter would always say
    // `null`.
    if (_cachedState == null) {
      return false;
    }

    final pending = _pendingRemoteChanges ??= <Change>[];
    if (pending.length + changes.length > _maxPendingRemoteChanges) {
      return false;
    }

    pending.addAll(changes);
    if (_replayBoundaryMatchesState) {
      // Keep the boundary at the maximum of what the state holds and what waits
      // in the queue. The commutative path can queue an older change, so the
      // last one is not always the newest.
      for (final change in changes) {
        final current = _replayBoundary;
        if (current == null || compareChangeOrder(change, current) > 0) {
          _replayBoundary = change;
        }
      }
    }
    _updateCachedVersion();
    return true;
  }

  /// Folds every queued change into the cached state.
  ///
  /// Anything that cannot be decoded or applied drops the cache, so the next
  /// read recomputes from the history — the same failure policy
  /// [_internalIncrementCachedState] uses.
  void _drainPendingRemoteChanges() {
    final pending = _pendingRemoteChanges;
    if (pending == null) {
      return;
    }
    _pendingRemoteChanges = null;

    if (_cachedState == null) {
      return;
    }
    var state = _cachedState as T;

    for (final change in pending) {
      final operation = _operationFromChange(change);
      if (operation == null) {
        invalidateCache();
        return;
      }
      final next = incrementCachedState(operation: operation, state: state);
      if (next == null) {
        invalidateCache();
        return;
      }
      state = next;
    }

    // The pinned version already covers these changes (see
    // [_queueRemoteChanges]), so only the state itself has to be stored.
    _cachedState = state;
  }

  /// Pins the cached version to the document's current version.
  void _updateCachedVersion() {
    _cachedVersion = Set.from(_document.version);
  }

  /// Replaces the cached state with [newState] and pins it to the current
  /// document version. Call this after a full recompute.
  void updateCachedState(T newState) {
    _cachedState = newState;
    _updateCachedVersion();
  }

  /// Framework hook: tries to advance the cache by a single [operation],
  /// honoring [useIncrementalCacheUpdate]. Falls back to [invalidateCache]
  /// when the host opts out, has no cached state, or cannot apply the
  /// operation incrementally.
  void _internalIncrementCachedState({required Operation operation}) {
    if (!useIncrementalCacheUpdate) {
      invalidateCache();
      return;
    }

    // A local operation must never land on a state that still has remote
    // changes waiting, so flush them first.
    _drainPendingRemoteChanges();

    final state = _cachedState;
    if (state == null) {
      return;
    }

    final newState = incrementCachedState(
      operation: operation,
      state: state,
    );

    if (newState == null) {
      invalidateCache();
      return;
    }

    updateCachedState(newState);

    // The change carrying this operation does not exist yet: it is created on
    // commit (see [_transactionFlushWork]). Until then the state holds an
    // operation with no place in the replay order, so the boundary is unknown.
    _replayBoundaryMatchesState = false;
  }

  /// Applies [operation] to [state] and returns the resulting state, or
  /// `null` to opt out of incremental updates (the cache will be
  /// invalidated and recomputed on the next read).
  ///
  /// May mutate [state] in place and return it. The default implementation
  /// returns `null`, i.e. no incremental path.
  T? incrementCachedState({
    required Operation operation,
    required T state,
  }) {
    return null;
  }

  /// Drops the cached state. The framework calls this automatically when
  /// the consumer's state is no longer guaranteed to match the document
  /// (e.g. external changes imported, snapshot merged, history pruned).
  void invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
    _pendingRemoteChanges = null;
    _replayBoundary = null;
    _replayBoundaryMatchesState = false;
  }

  /// The cached state if it still matches the document's current version,
  /// otherwise `null` (forcing the host to recompute).
  ///
  /// Reading it is what folds any queued remote change into the state, so a
  /// host never sees a cache that lags behind the document.
  T? get cachedState {
    _drainPendingRemoteChanges();

    if (_cachedState != null && setEquals(_cachedVersion, _document.version)) {
      return _cachedState;
    }

    return null;
  }
}

/// A provider that can provide a snapshot of the state of a [CRDTDocument]
///
/// Snapshot state is now a binary blob owned by the consumer. The framework
/// only frames each blob with a length prefix inside [Snapshot]; the encoding
/// and decoding of the blob's contents is entirely up to the consumer.
mixin SnapshotProvider on DocumentConsumer {
  @override
  String get id;

  /// Encodes the consumer's current state to a binary blob.
  ///
  /// The blob is opaque to `crdt_lf` itself and will be returned verbatim
  /// by [lastSnapshot] when the consumer needs to reconstruct its state.
  Uint8List getSnapshotState();

  /// Returns the last snapshot bytes for this consumer (the value previously
  /// produced by [getSnapshotState]) or `null` if no snapshot is available.
  Uint8List? lastSnapshot() {
    return _document._lastSnapshot?.data[id];
  }

  /// Returns the version vector of the last snapshot for this consumer.
  VersionVector? _snapshotVersionVector() {
    return _document._lastSnapshot?.versionVector;
  }
}

/// Helper extensions for [Handler]
extension _HandlerHelper on Handler<dynamic> {
  // Expando acts as a per-instance cache (weak-ref keyed map).
  // Extensions cannot declare instance fields, but an Expando on a static
  // variable gives the same semantics with no memory-leak risk.
  static final Expando<Uint8List> _prefixCache = Expando();

  /// Binary prefix for this handler's operations:
  /// [varint(typeLen)][type UTF-8][varint(idLen)][id UTF-8].
  ///
  /// Computed once and cached. Compared byte-by-byte against a change payload
  /// in [_isAffectedByChange] to avoid UTF-8 decode + String allocation on
  /// every change application.
  Uint8List get _envelopePrefix {
    return _prefixCache[this] ??= _buildPrefix();
  }

  Uint8List _buildPrefix() {
    final out = BytesBuilder(copy: false);
    final typeBytes = utf8.encode(handlerType);
    UVarint.write(typeBytes.length, out);
    out.add(typeBytes);
    final idBytes = utf8.encode(id);
    UVarint.write(idBytes.length, out);
    out.add(idBytes);
    return out.toBytes();
  }

  bool _isAffectedByChange(Change change) {
    final payload = change.payloadBytes();
    final prefix = _envelopePrefix;
    // +1 for the kind byte that follows the prefix.
    if (payload.length < prefix.length + 1) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (payload[i] != prefix[i]) return false;
    }
    return true;
  }
}
