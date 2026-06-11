import 'package:crdt_lf/crdt_lf.dart';

/// ChangeStore implementation for CRDT
///
/// A ChangeStore stores and manages changes to the CRDT state.
/// It provides methods for adding, retrieving, and exporting changes.
class ChangeStore {
  ChangeStore._(this._changes);

  /// Creates a new empty ChangeStore
  factory ChangeStore.empty() => ChangeStore._(<OpIdKey, Change>{});

  /// The changes stored in this [ChangeStore], indexed by their packed id.
  final Map<OpIdKey, Change> _changes;

  /// Per-peer changes sorted by clock, used to answer
  /// [exportChangesNewerThan] with a binary search instead of a full scan.
  ///
  /// Built lazily on first use, maintained by [addChange] and invalidated
  /// by [prune] and [clear]. `_changes` remains the source of truth.
  Map<PeerId, List<Change>>? _changesByPeer;

  /// Gets the number of changes in the store
  int get changeCount => _changes.length;

  /// Checks if the store contains a change with the given [id]
  bool containsChange(OperationId id) {
    return containsChangeKey(_keyFromOperationId(id));
  }

  /// Gets a change by its [id]
  Change? getChange(OperationId id) {
    return getChangeByKey(_keyFromOperationId(id));
  }

  /// Checks if the store contains a change with the given packed [id].
  bool containsChangeKey(OpIdKey id) {
    return _changes.containsKey(id);
  }

  /// Gets a change by its packed [id].
  Change? getChangeByKey(OpIdKey id) {
    return _changes[id];
  }

  /// Adds a [Change] to the store
  ///
  /// If a change with the same [Change.id] already exists, it is not replaced.
  /// Returns `true` if the [change] was added, `false` if it already existed.
  bool addChange(Change change) {
    final key = change.key;
    if (_changes.containsKey(key)) {
      return false;
    }

    _changes[key] = change;
    _indexChange(change);
    return true;
  }

  /// Keeps the per-peer index in sync with [addChange], when built.
  void _indexChange(Change change) {
    final index = _changesByPeer;
    if (index == null) {
      return;
    }

    final list = index.putIfAbsent(change.id.peerId, () => <Change>[]);
    if (list.isEmpty || list.last.hlc.compareTo(change.hlc) <= 0) {
      list.add(change);
      return;
    }

    // Out-of-order arrival: insert keeping the list sorted by clock
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].hlc.compareTo(change.hlc) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    list.insert(low, change);
  }

  /// Returns the per-peer index, building it from [_changes] if needed.
  Map<PeerId, List<Change>> _peerIndex() {
    final existing = _changesByPeer;
    if (existing != null) {
      return existing;
    }

    final index = <PeerId, List<Change>>{};
    for (final change in _changes.values) {
      index.putIfAbsent(change.id.peerId, () => <Change>[]).add(change);
    }
    for (final list in index.values) {
      list.sort((a, b) => a.hlc.compareTo(b.hlc));
    }
    return _changesByPeer = index;
  }

  /// Gets all [Change]s in the store
  List<Change> getAllChanges() {
    return _changes.values.toList();
  }

  /// Exports [Change]s from a specific version
  ///
  /// Returns a list of [Change]s that are not ancestors of the given [version].
  /// If [version] is empty, returns all [Change]s.
  List<Change> exportChanges(
    Set<OperationId> version,
    DAG dag,
  ) {
    if (version.isEmpty) {
      return getAllChanges();
    }

    // Get all ancestors of the version in a single traversal
    final ancestors = dag.getAncestorsOfAll(version);

    // Return all changes that are not ancestors of the version
    return _changes.values
        .where((change) => !ancestors.contains(change.id))
        .toList();
  }

  /// {@macro change_iterable_newer_than}
  List<Change> exportChangesNewerThan(VersionVector versionVector) {
    final result = <Change>[];

    for (final entry in _peerIndex().entries) {
      final list = entry.value;
      final clock = versionVector[entry.key];
      if (clock == null) {
        result.addAll(list);
        continue;
      }

      // Binary search for the first change with a strictly greater clock
      var low = 0;
      var high = list.length;
      while (low < high) {
        final mid = (low + high) >> 1;
        if (list[mid].hlc.compareTo(clock) > 0) {
          high = mid;
        } else {
          low = mid + 1;
        }
      }
      for (var i = low; i < list.length; i++) {
        result.add(list[i]);
      }
    }

    return result;
  }

  /// Imports [Change]s from another [ChangeStore]
  ///
  /// Returns the number of [Change]s that were added.
  int importChanges(List<Change> changes) {
    var added = 0;

    for (final change in changes) {
      if (addChange(change)) {
        added++;
      }
    }

    return added;
  }

  /// Removes [Change]s that are causally **older than**
  /// the provided [version] vector.
  ///
  /// If a [Change] has a dependency on a pruned [Change],
  /// the dependency is removed to preserve integrity.
  ///
  /// Returns the number of [Change]s that were removed.
  int prune(VersionVector version) {
    final removedIds = <OpIdKey>{};

    // 1. identify and remove old changes
    final ids = _changes.keys.toList();
    for (final id in ids) {
      final clock = version[id.peerId()];
      if (clock != null && id.hlc().compareTo(clock) <= 0) {
        _changes.remove(id);
        removedIds.add(id);
      }
    }

    if (removedIds.isEmpty) {
      return 0;
    }

    _changesByPeer = null;

    // 2. clean up dependencies in remaining changes.
    // Only changes that actually depend on a pruned change are rebuilt.
    final updates = <OpIdKey, Change>{};
    for (final entry in _changes.entries) {
      final change = entry.value;
      var hasPrunedDep = false;
      for (final depKey in change.depsKeys()) {
        if (removedIds.contains(depKey)) {
          hasPrunedDep = true;
          break;
        }
      }
      if (!hasPrunedDep) {
        continue;
      }

      final deps = <OperationId>{};
      for (final depKey in change.depsKeys()) {
        if (!removedIds.contains(depKey)) {
          deps.add(depKey.toOperationId());
        }
      }

      updates[entry.key] = Change.fromPayloadBytes(
        id: change.id,
        payloadBytes: change.payloadBytes(),
        deps: deps,
        author: change.author,
      );
    }
    _changes.addAll(updates);

    return removedIds.length;
  }

  static OpIdKey _keyFromOperationId(OperationId id) {
    return OpIdKey.copy(id.toUint8List());
  }

  /// Clears all [Change]s from the store
  void clear() {
    _changes.clear();
    _changesByPeer = null;
  }

  /// Returns a string representation of the [ChangeStore]
  @override
  String toString() {
    return 'ChangeStore(changes: ${_changes.length})';
  }
}
