import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

/// # CRDT OR-Set
///
/// ## Description
/// A CRDTORSet is a set data structure that uses
/// the Observed-Removed Set (OR-Set) algorithm to resolve conflicts.
///
/// ## Algorithm
/// Adding a value to the set produces a unique tag for the value.
/// Removing a value consists in tomb-stoning the tags for the value.
/// A value is considered present iff it has at least one tag not tomb-stoned.
///
/// More detail about OR-Set can be found in [this paper](https://inria.hal.science/inria-00555588/en/)
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final set = CRDTORSetHandler<String>(doc, 'set');
/// set.add('value1');
/// set.add('value2');
/// set.add('value3');
/// set.remove('value2');
/// print(set.value); // Prints {'value1', 'value3'}
/// ```
class CRDTORSetHandler<T> extends Handler<ORSetState<T>> {
  /// Creates a new CRDT OR-SetHandler with the given document and ID
  CRDTORSetHandler(super.doc, this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  late final OperationFactory operationFactory =
      _ORSetOperationFactory<T>(this).fromPayload;

  // TODO(mattia): create a reusable class for a tag related
  // to peerId and hlc. Can be shared with the ORMapHandler.
  /// Obtains a unique tag for an operation
  ORHandlerTag _tag() {
    doc.prepareMutation();
    return ORHandlerTag(
      peerId: doc.peerId,
      hlc: doc.hlc,
    );
  }

  /// Adds [value] to the set producing a unique tag, returned to the caller.
  ///
  /// The tag is pseudo-causal, derived from the current document clock
  /// and peer id, making it unique and loosely ordered.
  void add(T value) {
    final operation = _ORSetAddOperation<T>.fromHandler(
      this,
      value: value,
      tag: _tag(),
    );
    doc.registerOperation(operation);
  }

  /// Removes [value] from the set by tomb-stoning observed tags.
  void remove(T value) {
    final state = _cachedOrComputedState();
    final allTags = state._all[value] ?? <ORHandlerTag>{};

    final operation = _ORSetRemoveOperation<T>.fromHandler(
      this,
      value: value,
      tags: allTags,
    );
    doc.registerOperation(operation);
  }

  /// Returns the current set value computed from changes and snapshot.
  Set<T> get value {
    return _cachedOrComputedState()._state;
  }

  ORSetState<T> _cachedOrComputedState() {
    if (cachedState != null) {
      return cachedState!;
    }

    final tagState = _computeState();
    updateCachedState(tagState);
    return tagState;
  }

  /// Returns whether the set contains [value].
  bool contains(T element) => value.contains(element);

  /// Returns the current state for snapshotting
  @override
  List<T> getSnapshotState() {
    return value.toList();
  }

  /// Computes the tag state by replaying the history.
  ORSetState<T> _computeState() {
    final state = ORSetState<T>._(
      live: <T, Set<ORHandlerTag>>{},
      all: <T, Set<ORHandlerTag>>{},
      snapshotOnly: <T>{},
      tombstones: <ORHandlerTag>{},
    );

    final snap = lastSnapshot();

    // Seed from snapshot:
    // If a prior snapshot contained values for this handler,
    // we treat them as present without tags (snapshot-only) until changes say
    // otherwise.
    if (snap is List<dynamic> && snap.every((e) => e is T)) {
      for (final v in snap.cast<T>()) {
        state._snapshotOnly.add(v);
      }
    } else if (snap is Set<dynamic> && snap.every((e) => e is T)) {
      for (final v in snap.cast<T>()) {
        state._snapshotOnly.add(v);
      }
    }

    for (final operation in operations()) {
      _applyOperationToTagState(
        state: state,
        operation: operation,
      );
    }

    return state;
  }

  /// Applies a single operation to the tag state
  void _applyOperationToTagState({
    required ORSetState<T> state,
    required Operation operation,
  }) {
    if (operation is _ORSetAddOperation<T>) {
      _tagStateAdd(
        state: state,
        operation: operation,
      );
    } else if (operation is _ORSetRemoveOperation<T>) {
      _tagStateRemove(
        state: state,
        operation: operation,
      );
    }
  }

  void _tagStateAdd({
    required ORSetState<T> state,
    required _ORSetAddOperation<T> operation,
  }) {
    // Register tag as seen (all),
    // and as live if not tomb-stoned yet.
    state._all
        .putIfAbsent(operation.value, () => <ORHandlerTag>{})
        .add(operation.tag);
    if (!state._tombstones.contains(operation.tag)) {
      state._live
          .putIfAbsent(operation.value, () => <ORHandlerTag>{})
          .add(operation.tag);
    }
    // A concrete add overrides snapshot-only presence for this value.
    state._snapshotOnly.remove(operation.value);
  }

  void _tagStateRemove({
    required ORSetState<T> state,
    required _ORSetRemoveOperation<T> operation,
  }) {
    // Remove-all semantics apply when a remove is observed without tags.
    // This is used to remove snapshot-only presence.
    if (operation.removeAll) {
      // Remove snapshot-only presence for this value
      state._snapshotOnly.remove(operation.value);
    }

    // Tombstone all provided tags for the value and drop them from live.
    state._tombstones.addAll(operation.tags);

    final setLive = state._live[operation.value];
    if (setLive != null) {
      setLive.removeWhere(operation.tags.contains);
      if (setLive.isEmpty) {
        state._live.remove(operation.value);
      }
    }
  }

  @override
  ORSetState<T>? incrementCachedState({
    required Operation operation,
    required ORSetState<T> state,
  }) {
    final newState = state._deepCopy();

    // Apply the operation to the copied tag state
    _applyOperationToTagState(
      state: newState,
      operation: operation,
    );

    return newState;
  }
}

/// State of the [CRDTORSetHandler]
class ORSetState<T> {
  /// - [_live]: current non-tomb-stoned tags per value
  /// (value is present if non-empty)
  /// - [_all]: all tags ever observed per value
  /// (useful for computing default removals)
  /// - [_snapshotOnly]: values seeded from snapshot
  /// without any concrete add tags yet
  /// - [_tombstones]: set of tomb-stoned tags observed
  /// so far while replaying history.
  /// - [_state]: the current state of the OR-Set
  ORSetState._({
    required Map<T, Set<ORHandlerTag>> live,
    required Map<T, Set<ORHandlerTag>> all,
    required Set<T> snapshotOnly,
    required Set<ORHandlerTag> tombstones,
  })  : _tombstones = tombstones,
        _snapshotOnly = snapshotOnly,
        _all = all,
        _live = live;

  /// Creates a deep copy of the tag state
  ORSetState<T> _deepCopy() {
    final live = <T, Set<ORHandlerTag>>{
      for (final entry in _live.entries)
        entry.key: Set<ORHandlerTag>.from(entry.value),
    };
    final all = <T, Set<ORHandlerTag>>{
      for (final entry in _all.entries)
        entry.key: Set<ORHandlerTag>.from(entry.value),
    };
    final snapshotOnly = <T>{..._snapshotOnly};
    final tombstones = <ORHandlerTag>{..._tombstones};

    return ORSetState<T>._(
      live: live,
      all: all,
      snapshotOnly: snapshotOnly,
      tombstones: tombstones,
    );
  }

  /// The live tags per value
  final Map<T, Set<ORHandlerTag>> _live;

  /// The all tags per value
  final Map<T, Set<ORHandlerTag>> _all;

  /// The snapshot-only values
  final Set<T> _snapshotOnly;

  /// The tombstones
  final Set<ORHandlerTag> _tombstones;

  /// The state of the OR-Set
  Set<T> get _state => <T>{..._live.keys, ..._snapshotOnly};
}
