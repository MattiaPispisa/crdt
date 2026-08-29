import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

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
base class CRDTORSetHandler<T> extends Handler<ORSetState<T>>
    with DeltaProvider<Set<T>, SetDelta<T>> {
  /// Creates a new CRDT OR-SetHandler with the given document and ID
  ///
  /// [valueCodec] is an optional codec for encoding/decoding [T] values to bytes.
  /// Default is [JsonValueCodec].
  CRDTORSetHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final String _id;
  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _ORSetAddOperation<T>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _ORSetRemoveOperation<T>.fromBodyBytes(this, body),
  };

  /// The stamp of an `add` is the tag it stores for the added value.
  @override
  late final OperationType insertType = OperationType.insert(
    this,
    stamped: true,
  );

  /// Adds [value] to the set under a tag of its own.
  ///
  /// The tag is the [OperationId] the document mints for the operation, so
  /// two peers adding the same value concurrently produce two tags and the
  /// value survives either removal.
  void add(T value) {
    final operation = _ORSetAddOperation<T>.fromHandler(
      this,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Removes [value] from the set by tomb-stoning observed tags.
  void remove(T value) {
    final state = _cachedOrComputedState();
    final allTags = state._all[value] ?? <OperationId>{};

    final operation = _ORSetRemoveOperation<T>.fromHandler(
      this,
      value: value,
      tags: allTags,
    );
    doc.registerOperation(operation);
  }

  /// Returns the current set value computed from changes and snapshot.
  ///
  /// Every read builds a fresh set, so the caller owns what it gets back and
  /// can keep it.
  @override
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

  /// The version of the snapshot blob this build writes and reads.
  ///
  /// Layout: `version: u8`, `count: uvarint`, then per item
  /// `itemLen: uvarint`, `item: bytes`. The tags stay out: a snapshot holds
  /// the projected set, and the elements come back tagless.
  static const int _snapshotVersion = 1;

  /// Returns the current state for snapshotting as a binary blob.
  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    final items = value;
    UVarint.write(items.length, out);
    for (final item in items) {
      UVarint.writeBytes(_valueCodec.encode(item), out);
    }
    return out.toBytes();
  }

  /// Computes the tag state by replaying the history.
  ORSetState<T> _computeState() {
    final state = ORSetState<T>._(
      live: <T, Set<OperationId>>{},
      all: <T, Set<OperationId>>{},
      snapshotOnly: <T>{},
      tombstones: <OperationId>{},
    );

    final snap = lastSnapshot();

    // Seed from snapshot:
    // If a prior snapshot contained values for this handler,
    // we treat them as present without tags (snapshot-only) until changes say
    // otherwise. The snapshot is a length-prefixed sequence of items encoded
    // via [_valueCodec].
    if (snap != null) {
      var offset = SnapshotBlob.read(
        snap,
        version: _snapshotVersion,
        name: 'OR-set',
      );
      final countRec = UVarint.read(snap, offset: offset);
      offset = countRec.nextOffset;
      for (var i = 0; i < countRec.value; i += 1) {
        final valueRecord = UVarint.readBytes(
          snap,
          offset: offset,
          what: 'OR-set snapshot value',
        );
        state._snapshotOnly.add(_valueCodec.decode(valueRecord.value));
        offset = valueRecord.nextOffset;
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

  /// The value an operation is about, or `null` for a kind that is about no
  /// single value.
  ///
  /// A record rather than a bare `T?`: a set of a nullable type can hold
  /// `null`, and "this operation is about `null`" must not read as "this
  /// operation is about nothing".
  (T,)? _targetValue(Operation operation) {
    if (operation is _ORSetAddOperation<T>) {
      return (operation.value,);
    }
    if (operation is _ORSetRemoveOperation<T>) {
      return (operation.value,);
    }
    return null;
  }

  /// Whether [value] is in the set, without building the whole set.
  bool _isPresent(ORSetState<T> state, T value) =>
      state._live.containsKey(value) || state._snapshotOnly.contains(value);

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
    //
    // The stamp is there for every add: the handler is stamped, so the
    // document mints one locally and the decode refuses a change without one.
    final tag = operation.stamp!;
    state._all.putIfAbsent(operation.value, () => <OperationId>{}).add(tag);
    if (!state._tombstones.contains(tag)) {
      state._live.putIfAbsent(operation.value, () => <OperationId>{}).add(tag);
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
      for (final tag in operation.tags) {
        setLive.remove(tag);
      }
      if (setLive.isEmpty) {
        state._live.remove(operation.value);
      }
    }
  }

  @override
  bool get stateIsOrderIndependent => true;

  @override
  ORSetState<T>? incrementCachedState({
    required Operation operation,
    required ORSetState<T> state,
    DeltaSink<Object?>? sink,
  }) {
    // The cached state is never exposed by this handler, so it can be
    // mutated in place instead of deep-copied on every operation.
    try {
      // The operations are tag-level: an add of a value that already has a
      // live tag moves the tags but not the set anyone can see. So the delta
      // comes from membership before and after, one O(1) lookup each.
      final target = _targetValue(operation);
      final before = target != null && _isPresent(state, target.$1);

      _applyOperationToTagState(
        state: state,
        operation: operation,
      );

      if (sink != null) {
        final after = target != null && _isPresent(state, target.$1);
        sink.add(
          SetDelta<T>(
            added: !before && after ? <T>{target.$1} : <T>{},
            removed: before && !after ? <T>{target.$1} : <T>{},
          ),
        );
      }
      return state;
    } catch (_) {
      // The state may be half-mutated: invalidate the cache.
      return null;
    }
  }

  @override
  Set<T> applyDelta(Set<T> base, SetDelta<T> delta) => delta.apply(base);
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
    required Map<T, Set<OperationId>> live,
    required Map<T, Set<OperationId>> all,
    required Set<T> snapshotOnly,
    required Set<OperationId> tombstones,
  })  : _tombstones = tombstones,
        _snapshotOnly = snapshotOnly,
        _all = all,
        _live = live;

  /// The live tags per value
  final Map<T, Set<OperationId>> _live;

  /// The all tags per value
  final Map<T, Set<OperationId>> _all;

  /// The snapshot-only values
  final Set<T> _snapshotOnly;

  /// The tombstones
  final Set<OperationId> _tombstones;

  /// The state of the OR-Set
  Set<T> get _state => <T>{..._live.keys, ..._snapshotOnly};
}
