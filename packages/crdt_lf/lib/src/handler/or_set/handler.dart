import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

/// Observed-Removed Set (OR-Set) handler
///
/// Conflict resolution follows Observed-Removed semantics:
/// - Each add produces a unique tag for the value.
/// - Remove tombstones the set of observed tags for a value.
/// - A value is present iff it has at least one tag not tomb-stoned.
class CRDTORSetHandler<T> extends Handler<Set<T>> {
  /// Creates a new CRDT OR-SetHandler with the given document and ID
  CRDTORSetHandler(super.doc, this._id);

  final String _id;

  @override
  String get id => _id;

  String _tag() {
    return '${doc.peerId}@${doc.hlc}';
  }

  /// Adds [value] to the set producing a unique tag, returned to the caller.
  ///
  /// The tag is pseudo-causal, derived from the current document clock
  /// and peer id, making it unique and loosely ordered.
  void add(T value) {
    doc.createChange(
      _ORSetAddOperation<T>.fromHandler(
        this,
        value: value,
        tag: _tag(),
      ),
    );
    invalidateCache();
  }

  /// Removes [value] from the set by tomb-stoning observed tags.
  void remove(T value) {
    final state = _computeTagState();
    final allTags = state.all[value] ?? <String>{};

    doc.createChange(
      _ORSetRemoveOperation<T>.fromHandler(
        this,
        value: value,
        tags: allTags,
      ),
    );
    invalidateCache();
  }

  /// Returns the current set value computed from changes and snapshot.
  Set<T> get value {
    if (cachedState != null) {
      return cachedState!;
    }

    final state = _computeState();
    updateCachedState(state);
    return Set.from(state);
  }

  /// Returns whether the set contains [value].
  bool contains(T element) => value.contains(element);

  /// Returns the current state for snapshotting
  @override
  Set<T> getSnapshotState() {
    return value;
  }

  /// Computes the state as per OR-Set rules
  Set<T> _computeState() {
    final tagState = _computeTagState();
    return <T>{...tagState.live.keys, ...tagState.snapshotOnly};
  }

  /// Computes the tag state by replaying the history.
  _TagState<T> _computeTagState() {
    final live = <T, Set<String>>{};
    final all = <T, Set<String>>{};
    final snapshotOnly = <T>{};

    // Global set of tomb-stoned tags observed
    // so far while replaying history.
    final tombstones = <String>{};

    final snap = lastSnapshot();
    final changes = doc.exportChanges().sorted();

    // Seed from snapshot:
    // If a prior snapshot contained values for this handler,
    // we treat them as present without tags (snapshot-only) until changes say
    // otherwise.
    if (snap is Set<dynamic> && snap.every((e) => e is T)) {
      for (final v in snap.cast<T>()) {
        snapshotOnly.add(v);
      }
    }

    final opFactory = _ORSetOperationFactory<T>(this);

    for (final change in changes) {
      final op = opFactory.fromPayload(change.payload);
      if (op is _ORSetAddOperation<T>) {
        // Register tag as seen (all),
        // and as live if not tomb-stoned yet.
        all.putIfAbsent(op.value, () => <String>{}).add(op.tag);
        if (!tombstones.contains(op.tag)) {
          live.putIfAbsent(op.value, () => <String>{}).add(op.tag);
        }
        // A concrete add overrides snapshot-only presence for this value.
        snapshotOnly.remove(op.value);
      } else if (op is _ORSetRemoveOperation<T>) {
        // Remove-all semantics apply when a remove is observed without tags.
        // This is used to remove snapshot-only presence.
        if (op.removeAll) {
          // Remove snapshot-only presence for this value
          snapshotOnly.remove(op.value);
        }
        // Tombstone all provided tags for the value and drop them from live.
        for (final tag in op.tags) {
          tombstones.add(tag);
        }
        final setLive = live[op.value];
        if (setLive != null) {
          setLive.removeWhere(op.tags.contains);
          if (setLive.isEmpty) {
            live.remove(op.value);
          }
        }
      }
    }

    return _TagState<T>(
      live: live,
      all: all,
      snapshotOnly: snapshotOnly,
    );
  }
}

/// - [live]: current non-tomb-stoned tags per value
/// (value is present if non-empty)
/// - [all]: all tags ever observed per value
/// (useful for computing default removals)
/// - [snapshotOnly]: values seeded from snapshot without any concrete add tags
/// yet
class _TagState<T> {
  _TagState({
    required this.live,
    required this.all,
    required this.snapshotOnly,
  });
  final Map<T, Set<String>> live;
  final Map<T, Set<String>> all;
  final Set<T> snapshotOnly;
}
