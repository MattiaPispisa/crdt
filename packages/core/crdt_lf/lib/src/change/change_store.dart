import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

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

  /// Secondary index used to answer [exportChangesNewerThan];
  /// `_changes` remains the source of truth.
  final _PeerClockIndex _peerClockIndex = _PeerClockIndex();

  /// Secondary index used to answer [changesForHandler];
  /// `_changes` remains the source of truth.
  final _HandlerIndex _handlerIndex = _HandlerIndex();

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
    _peerClockIndex.add(change);
    _handlerIndex.add(change);
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

    // Get all ancestors of the version in a single traversal
    final ancestors = dag.getAncestorsOfAll(version);

    // Return all changes that are not ancestors of the version
    return _changes.values
        .where((change) => !ancestors.contains(change.id))
        .toList();
  }

  /// {@macro change_iterable_newer_than}
  List<Change> exportChangesNewerThan(VersionVector versionVector) {
    return _peerClockIndex.changesNewerThan(versionVector, _changes.values);
  }

  /// Returns the [Change]s produced by the handler with the given [handlerId].
  ///
  /// If [fromVersionVector] is provided, only changes strictly newer than it
  /// (per author) are returned. Backed by a secondary index, so the cost is
  /// proportional to the handler's own changes instead of a full scan of the
  /// store.
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  }) {
    return _handlerIndex.changesForHandler(
      handlerId,
      fromVersionVector,
      _changes.values,
    );
  }

  /// Returns the number of [Change]s produced by the handler with the given
  /// [handlerId].
  ///
  /// Backed by the same secondary index as [changesForHandler] but O(1) and
  /// without allocating a list — suited to being polled.
  int changeCountForHandler(String handlerId) {
    return _handlerIndex.countForHandler(handlerId, _changes.values);
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
      if (clock != null && id.hlc() <= clock) {
        _changes.remove(id);
        removedIds.add(id);
      }
    }

    if (removedIds.isEmpty) {
      return 0;
    }

    _peerClockIndex.invalidate();
    _handlerIndex.invalidate();

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
    _peerClockIndex.invalidate();
    _handlerIndex.invalidate();
  }

  /// Returns a string representation of the [ChangeStore]
  @override
  String toString() {
    return 'ChangeStore(changes: ${_changes.length})';
  }
}

/// Secondary index of [Change]s grouped by peer and sorted by clock.
///
/// Answers [ChangeStore.exportChangesNewerThan] with a binary search per
/// peer instead of a full scan of the store.
///
/// The index is built lazily from the source of truth (the store's primary
/// map) on the first query, kept in sync by [add] on every insertion and
/// dropped by [invalidate] when changes are removed or rewritten.
class _PeerClockIndex {
  Map<PeerId, List<Change>>? _byPeer;

  /// Keeps the index in sync with an insertion, when built.
  void add(Change change) {
    final index = _byPeer;
    if (index == null) {
      return;
    }

    final list = index.putIfAbsent(change.id.peerId, () => <Change>[]);
    if (list.isEmpty || list.last.hlc <= change.hlc) {
      list.add(change);
      return;
    }

    // Out-of-order arrival: insert keeping the list sorted by clock
    list.insert(_firstNewerThan(list, change.hlc), change);
  }

  /// Drops the index; it is rebuilt lazily on the next query.
  void invalidate() {
    _byPeer = null;
  }

  /// {@macro change_iterable_newer_than}
  ///
  /// [source] is the store's current set of changes, used to (re)build the
  /// index when it is not available.
  List<Change> changesNewerThan(
    VersionVector versionVector,
    Iterable<Change> source,
  ) {
    final index = _byPeer ??= _build(source);
    final result = <Change>[];

    for (final entry in index.entries) {
      final list = entry.value;
      final clock = versionVector[entry.key];
      if (clock == null) {
        result.addAll(list);
        continue;
      }

      for (var i = _firstNewerThan(list, clock); i < list.length; i++) {
        result.add(list[i]);
      }
    }

    return result;
  }

  static Map<PeerId, List<Change>> _build(Iterable<Change> source) {
    final index = <PeerId, List<Change>>{};
    for (final change in source) {
      index.putIfAbsent(change.id.peerId, () => <Change>[]).add(change);
    }
    for (final list in index.values) {
      list.sort((a, b) => a.hlc.compareTo(b.hlc));
    }
    return index;
  }

  /// Returns the index of the first change in the sorted [list] with a
  /// clock strictly greater than [clock], or `list.length` if none.
  static int _firstNewerThan(List<Change> list, HybridLogicalClock clock) {
    // binary search (lower bound)
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].hlc > clock) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}

/// Secondary index of [Change]s grouped by the id of the handler that produced
/// them (read from the operation envelope).
///
/// Answers [ChangeStore.changesForHandler] in time proportional to the
/// handler's own changes instead of a full scan of the store — the hot path
/// when many handlers (e.g. nested containers and leaves) replay their state.
///
/// Built lazily from the source of truth on the first query, kept in sync by
/// [add] on every insertion and dropped by [invalidate] when changes are
/// removed or rewritten.
class _HandlerIndex {
  Map<String, List<Change>>? _byHandler;

  /// Keeps the index in sync with an insertion, when built.
  void add(Change change) {
    final index = _byHandler;
    if (index == null) {
      return;
    }
    index.putIfAbsent(_handlerIdOf(change), () => <Change>[]).add(change);
  }

  /// Drops the index; it is rebuilt lazily on the next query.
  void invalidate() {
    _byHandler = null;
  }

  /// Returns the changes for [handlerId], optionally filtered to those newer
  /// than [versionVector] (per author).
  ///
  /// [source] is the store's current set of changes, used to (re)build the
  /// index when it is not available.
  List<Change> changesForHandler(
    String handlerId,
    VersionVector? versionVector,
    Iterable<Change> source,
  ) {
    final index = _byHandler ??= _build(source);
    final list = index[handlerId];
    if (list == null) {
      return <Change>[];
    }
    if (versionVector == null) {
      return list.toList();
    }
    return list.where((change) {
      final clock = versionVector[change.author];
      return clock == null || change.hlc.happenedAfter(clock);
    }).toList();
  }

  /// Returns the number of changes for [handlerId] in O(1) (once the index is
  /// built), without allocating a list.
  ///
  /// [source] is the store's current set of changes, used to (re)build the
  /// index when it is not available.
  int countForHandler(String handlerId, Iterable<Change> source) {
    final index = _byHandler ??= _build(source);
    return index[handlerId]?.length ?? 0;
  }

  static Map<String, List<Change>> _build(Iterable<Change> source) {
    final index = <String, List<Change>>{};
    for (final change in source) {
      index.putIfAbsent(_handlerIdOf(change), () => <Change>[]).add(change);
    }
    return index;
  }

  static String _handlerIdOf(Change change) {
    return OperationEnvelopeCodec.decode(change.payloadBytes()).handlerId;
  }
}
