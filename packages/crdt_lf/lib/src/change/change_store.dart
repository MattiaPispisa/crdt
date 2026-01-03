import 'package:crdt_lf/crdt_lf.dart';

/// ChangeStore implementation for CRDT
///
/// A ChangeStore stores and manages changes to the CRDT state.
/// It provides methods for adding, retrieving, and exporting changes.
class ChangeStore {
  ChangeStore._(this._changes);

  /// Creates a new empty ChangeStore
  factory ChangeStore.empty() => ChangeStore._(<OperationId, Change>{});

  /// The changes stored in this [ChangeStore], indexed by their [OperationId]
  final Map<OperationId, Change> _changes;

  /// Gets the number of changes in the store
  int get changeCount => _changes.length;

  /// Checks if the store contains a change with the given [id]
  bool containsChange(OperationId id) {
    return _changes.containsKey(id);
  }

  /// Gets a change by its [id]
  Change? getChange(OperationId id) {
    return _changes[id];
  }

  /// Adds a [Change] to the store
  ///
  /// If a change with the same [Change.id] already exists, it is not replaced.
  /// Returns `true` if the [change] was added, `false` if it already existed.
  bool addChange(Change change) {
    if (_changes.containsKey(change.id)) {
      return false;
    }

    _changes[change.id] = change;
    return true;
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

    // Get all ancestors of the version
    final ancestors = <OperationId>{};
    for (final id in version) {
      ancestors.addAll(dag.getAncestors(id));
    }

    // Return all changes that are not ancestors of the version
    return _changes.values
        .where((change) => !ancestors.contains(change.id))
        .toList();
  }

  /// {@macro change_iterable_newer_than}
  List<Change> exportChangesNewerThan(VersionVector versionVector) {
    return _changes.values.newerThan(versionVector).toList();
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
    final removedIds = <OperationId>{};

    // 1. identify and remove old changes
    var ids = _changes.keys.toList();
    for (final id in ids) {
      final clock = version[id.peerId];
      if (clock != null && id.hlc.compareTo(clock) <= 0) {
        _changes.remove(id);
        removedIds.add(id);
      }
    }

    if (removedIds.isEmpty) {
      return 0;
    }

    // 2. clean up dependencies in remaining changes
    ids = _changes.keys.toList();
    for (final id in ids) {
      // Remove dependencies to pruned changes
      _changes.update(id, (change) {
        return Change.fromPayload(
          id: change.id,
          payload: change.payload,
          deps: Set.from(change.deps)..removeWhere(removedIds.contains),
          author: change.author,
        );
      });
    }

    return removedIds.length;
  }

  /// Clears all [Change]s from the store
  void clear() {
    _changes.clear();
  }

  /// Returns a string representation of the [ChangeStore]
  @override
  String toString() {
    return 'ChangeStore(changes: ${_changes.length})';
  }
}
