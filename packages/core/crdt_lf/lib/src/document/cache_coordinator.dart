// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'document.dart';

/// Keeps the cached state of the open handlers in step with the document,
/// and the revisions behind [BaseCRDTDocument.revisionForHandler].
///
/// Every revision bump happens here.
final class _CacheCoordinator {
  _CacheCoordinator(this._registry)
      : _revisions = {},
        _refHolders = {},
        _indexedRefs = {},
        _staleContainers = {};

  final _HandlerRegistry _registry;

  /// What a cached handler state is pinned to; [markAllStale] moves it.
  int get epoch => _epoch;
  int _epoch = 0;

  /// Makes every cached state stale at once: the next read rebuilds it.
  ///
  /// For the paths that move the base every state is replayed from. A change
  /// does not need it: it reaches the one handler it targets, and the others
  /// have nothing to catch up on.
  void markAllStale() => _epoch++;

  final Map<String, int> _revisions;

  /// The open containers that referenced each child id when last indexed.
  ///
  /// May name a container that has since dropped the reference: the only cost
  /// is one extra revision bump.
  final Map<String, Set<String>> _refHolders;

  /// The child ids of each indexed container; the inverse of [_refHolders].
  final Map<String, Set<String>> _indexedRefs;

  /// The open containers whose references may have changed since they were
  /// last indexed. A delete reads only these, so its cost follows the edits
  /// since the last delete, not the number of open handlers.
  final Set<String> _staleContainers;

  int revisionOf(String handlerId) => _revisions[handlerId] ?? 0;

  /// Moves the revision of [id] after a change to its state.
  void bumpState(String id) {
    _bumpView(id);
    if (_registry[id] is ContainerHandler) {
      _staleContainers.add(id);
    }
  }

  /// Moves the revision of [id] when it reads differently with its state
  /// unchanged: it, or a child it references, was deleted.
  void _bumpView(String id) {
    _revisions.update(id, (r) => r + 1, ifAbsent: () => 1);
  }

  /// Moves the revision of every handler whose state [snapshot] carries.
  void bumpForSnapshot(Snapshot snapshot) {
    SnapshotRecords.handlerIdsOf(snapshot).forEach(bumpState);
  }

  /// Moves the revision of each of [closed], and of the open containers that
  /// reference one of them.
  ///
  /// Call it before [closed] are marked deleted: a container read after that
  /// no longer lists a deleted child, so its revision would stay put.
  void bumpDeleted(Set<String> closed) {
    _reindexStaleContainers();
    final holders = {
      for (final id in closed) ...?_refHolders.remove(id),
    }..removeAll(closed);
    for (final id in holders.followedBy(closed)) {
      _bumpView(id);
    }
  }

  /// Starts following [handler], which just opened.
  void track(Handler<dynamic> handler) {
    if (handler is ContainerHandler) {
      _staleContainers.add(handler.id);
    }
  }

  /// Stops following the handler [id], which is closing.
  void forget(String id) {
    _staleContainers.remove(id);
    _dropIndexedRefs(id);
  }

  void _reindexStaleContainers() {
    final stale = _staleContainers.toList();
    _staleContainers.clear();
    for (final id in stale) {
      _dropIndexedRefs(id);
      if (_registry[id] case final ContainerHandler container) {
        final children = {for (final ref in container.childRefs()) ref.id};
        _indexedRefs[id] = children;
        for (final child in children) {
          (_refHolders[child] ??= {}).add(id);
        }
      }
    }
  }

  void _dropIndexedRefs(String containerId) {
    final children = _indexedRefs.remove(containerId);
    if (children == null) {
      return;
    }
    for (final child in children) {
      final holders = _refHolders[child];
      if (holders == null) {
        continue;
      }
      holders.remove(containerId);
      if (holders.isEmpty) {
        _refHolders.remove(child);
      }
    }
  }

  /// Hands [change], applied to the document, to the cache of its handler.
  ///
  /// For a change **no handler has folded into its cache yet**. It can sort
  /// before what its handler already holds, so the handler either queues it
  /// (see [CacheableStateProvider._queueRemoteChanges]) or drops its cache.
  void route(Change change) {
    final handler = _registry.forPayload(change.payloadBytes());
    if (handler != null) {
      _refresh(handler, [change]);
    }
  }

  /// Batch version of [route].
  ///
  /// Groups the batch by handler once, then refreshes only the handlers it
  /// targets: the cost follows the batch, not the number of handlers.
  void routeAll(List<Change> changes) {
    if (_registry.isEmpty) {
      return;
    }
    final affected = <Handler<dynamic>, List<Change>>{};
    for (final change in changes) {
      final handler = _registry.forPayload(change.payloadBytes());
      if (handler == null) {
        continue;
      }
      final pending = affected[handler];
      if (pending == null) {
        affected[handler] = <Change>[change];
      } else if (pending.isNotEmpty) {
        pending.add(change);
        if (pending.length > CacheableStateProvider._maxPendingRemoteChanges) {
          // Too many to queue: mark the handler for invalidation and stop
          // holding on to its changes.
          affected[handler] = const <Change>[];
        }
      }
    }
    affected.forEach(_refresh);
  }

  /// Refreshes the cache of [handler] after external [pending] changes that
  /// target it.
  ///
  /// The revision moves and the changes are queued, falling back to
  /// invalidation when the handler cannot take them. An empty [pending] means
  /// touched, but to be invalidated outright.
  void _refresh(Handler<dynamic> handler, List<Change> pending) {
    bumpState(handler.id);
    if (!handler._queueRemoteChanges(pending)) {
      handler.invalidateCache();
      return;
    }

    // A watched handler cannot leave the queue waiting for a read that may
    // never come, so it folds now and publishes one event per change.
    if (handler.hasDeltaListeners) {
      try {
        handler._drainPendingRemoteChanges(withDeltas: true);
      } catch (_) {
        // The drain has already dropped this handler's cache and told its
        // subscribers why. Letting the throw out would leave the other handlers
        // of a batch with their changes neither queued nor dropped — and
        // reading this one still recomputes, and still throws, exactly as it
        // does when nobody is watching.
      }
    }
  }

  /// Drops the cache of every open handler, telling a watcher [cause].
  void invalidateAll(ResetCause cause) {
    for (final handler in _registry.values) {
      handler._invalidate(cause);
    }
  }

  void clear() {
    _refHolders.clear();
    _indexedRefs.clear();
    _staleContainers.clear();
  }
}
