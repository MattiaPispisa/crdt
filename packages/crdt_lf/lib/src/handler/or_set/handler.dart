import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

/// Observed-Removed Set (OR-Set) handler
///
/// Conflict resolution follows Observed-Removed semantics:
/// - Each add produces a unique tag for the value.
/// - Remove tombstones the set of observed tags for a value.
/// - A value is present iff it has at least one tag not tomb-stoned.
class CRDTORSetHandler<T> extends Handler<ORSetState<T>> {
  /// Creates a new CRDT OR-SetHandler with the given document and ID
  CRDTORSetHandler(super.doc, this._id);

  final String _id;

  @override
  String get id => _id;

  /// Obtains a unique tag for an operation
  String _tag() {
    return '${doc.peerId}@${doc.hlc}';
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
    doc.createChange(operation);
  }

  /// Removes [value] from the set by tomb-stoning observed tags.
  void remove(T value) {
    final state = cachedState ?? _computeState();
    final allTags = state.all[value] ?? <String>{};

    final operation = _ORSetRemoveOperation<T>.fromHandler(
      this,
      value: value,
      tags: allTags,
    );
    doc.createChange(operation);
  }

  /// Returns the current set value computed from changes and snapshot.
  Set<T> get value {
    if (cachedState != null) {
      return cachedState!.state;
    }

    final tagState = _computeState();
    updateCachedState(tagState);
    return tagState.state;
  }

  /// Returns whether the set contains [value].
  bool contains(T element) => value.contains(element);

  /// Returns the current state for snapshotting
  @override
  Set<T> getSnapshotState() {
    return value;
  }

  /// Computes the tag state by replaying the history.
  ORSetState<T> _computeState() {
    final state = ORSetState<T>(
      live: <T, Set<String>>{},
      all: <T, Set<String>>{},
      snapshotOnly: <T>{},
      tombstones: <String>{},
    );

    final snap = lastSnapshot();
    final changes = doc.exportChanges().sorted();

    // Seed from snapshot:
    // If a prior snapshot contained values for this handler,
    // we treat them as present without tags (snapshot-only) until changes say
    // otherwise.
    if (snap is Set<dynamic> && snap.every((e) => e is T)) {
      for (final v in snap.cast<T>()) {
        state.snapshotOnly.add(v);
      }
    }

    final opFactory = _ORSetOperationFactory<T>(this);

    for (final change in changes) {
      final op = opFactory.fromPayload(change.payload);
      if (op != null) {
        _applyOperationToTagState(
          state: state,
          operation: op,
        );
      }
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
    state.all.putIfAbsent(operation.value, () => <String>{}).add(operation.tag);
    if (!state.tombstones.contains(operation.tag)) {
      state.live
          .putIfAbsent(operation.value, () => <String>{})
          .add(operation.tag);
    }
    // A concrete add overrides snapshot-only presence for this value.
    state.snapshotOnly.remove(operation.value);
  }

  void _tagStateRemove({
    required ORSetState<T> state,
    required _ORSetRemoveOperation<T> operation,
  }) {
    // Remove-all semantics apply when a remove is observed without tags.
    // This is used to remove snapshot-only presence.
    if (operation.removeAll) {
      // Remove snapshot-only presence for this value
      state.snapshotOnly.remove(operation.value);
    }

    // Tombstone all provided tags for the value and drop them from live.
    state.tombstones.addAll(operation.tags);

    final setLive = state.live[operation.value];
    if (setLive != null) {
      setLive.removeWhere(operation.tags.contains);
      if (setLive.isEmpty) {
        state.live.remove(operation.value);
      }
    }
  }

  @override
  ORSetState<T> incrementCachedState({
    required Operation operation,
    required ORSetState<T> state,
  }) {
    final newState = state.deepCopy();

    // Apply the operation to the copied tag state
    _applyOperationToTagState(
      state: newState,
      operation: operation,
    );

    return newState;
  }
}

/// - [live]: current non-tomb-stoned tags per value
/// (value is present if non-empty)
/// - [all]: all tags ever observed per value
/// (useful for computing default removals)
/// - [snapshotOnly]: values seeded from snapshot without any concrete add tags
/// yet
/// - [tombstones]: set of tomb-stoned tags observed
/// so far while replaying history.
/// - [state]: the current state of the OR-Set
class ORSetState<T> {
  /// Creates a new ORSetState
  ORSetState({
    required this.live,
    required this.all,
    required this.snapshotOnly,
    required this.tombstones,
  });

  /// Creates a deep copy of the tag state
  ORSetState<T> deepCopy() {
    final live = <T, Set<String>>{
      for (final entry in this.live.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final all = <T, Set<String>>{
      for (final entry in this.all.entries)
        entry.key: Set<String>.from(entry.value),
    };
    final snapshotOnly = <T>{...this.snapshotOnly};
    final tombstones = <String>{...this.tombstones};

    return ORSetState<T>(
      live: live,
      all: all,
      snapshotOnly: snapshotOnly,
      tombstones: tombstones,
    );
  }

  /// The live tags per value
  final Map<T, Set<String>> live;

  /// The all tags per value
  final Map<T, Set<String>> all;

  /// The snapshot-only values
  final Set<T> snapshotOnly;

  /// The tombstones
  final Set<String> tombstones;

  /// The state of the OR-Set
  Set<T> get state => <T>{...live.keys, ...snapshotOnly};
}
