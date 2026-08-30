import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

part 'operation.dart';

/// # CRDT OR-Map
///
/// ## Description
/// A CRDTORMap is a map data structure that uses
/// the Observed-Removed Map (OR-Map) algorithm to resolve conflicts.
///
/// ## Algorithm
/// Adding or updating a key-value pair produces a unique tag for the pair.
/// Removing a key consists in tomb-stoning all tags for that key.
/// A key is considered present iff it has at least one tag not tomb-stoned.
///
/// More detail about OR-Set (the foundation) can be found in
/// [this paper](https://inria.hal.science/inria-00555588/en/)
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final map = CRDTORMapHandler<String, int>(doc, 'map');
/// map.put('a', 1);
/// map.put('b', 2);
/// map.put('a', 10); // Update value for key 'a'
/// map.remove('b');
/// print(map.value); // Prints {'a': 10}
/// ```
base class CRDTORMapHandler<K, V> extends Handler<ORMapState<K, V>>
    with
        RebuiltIdentities<OperationId>,
        DeltaProvider<Map<K, V>, MapDelta<K, V>> {
  /// Creates a new CRDT OR-MapHandler with the given document and ID
  ///
  /// [keyCodec] and [valueCodec] are optional codecs for encoding/decoding keys and values to bytes.
  /// Default is [JsonValueCodec].
  CRDTORMapHandler(
    super.doc,
    this._id, {
    ValueCodec<K>? keyCodec,
    ValueCodec<V>? valueCodec,
    super.handlerType,
  })  : _keyCodec = keyCodec ?? JsonValueCodec<K>(),
        _valueCodec = valueCodec ?? JsonValueCodec<V>();

  final String _id;
  final ValueCodec<K> _keyCodec;
  final ValueCodec<V> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _ORMapPutOperation<K, V>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _ORMapRemoveOperation<K, V>.fromBodyBytes(this, body),
  };

  /// The stamp of a `put` is the tag it stores for the written value.
  @override
  late final OperationType insertType = OperationType.insert(
    this,
    stamped: true,
  );

  /// Puts [value] for [key] in the map, under a tag of its own.
  ///
  /// Writing a key that already exists adds a new tag rather than replacing
  /// the old one, which is how the key reads back as updated. The tag is the
  /// [OperationId] the document mints for the operation, so two peers
  /// writing the same key concurrently converge on the higher stamp.
  void put(K key, V value) {
    final operation = _ORMapPutOperation<K, V>.fromHandler(
      this,
      key: key,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Removes [key] from the map by tomb-stoning all observed tags for that key.
  void remove(K key) {
    final state = _cachedOrComputedState();
    final allTagsForKey = state._allTagsForKey(key);

    final operation = _ORMapRemoveOperation<K, V>.fromHandler(
      this,
      key: key,
      tags: allTagsForKey,
    );
    doc.registerOperation(operation);
  }

  /// Returns the current map value computed from changes and snapshot.
  ///
  /// Every read builds a fresh map, so the caller owns what it gets back and
  /// can keep it.
  @override
  Map<K, V> get value {
    return _cachedOrComputedState()._state;
  }

  ORMapState<K, V> _cachedOrComputedState() {
    if (cachedState != null) {
      return cachedState!;
    }

    final tagState = _computeState();
    updateCachedState(tagState);
    return tagState;
  }

  /// Returns whether the map contains [key].
  bool containsKey(K key) => value.containsKey(key);

  /// Returns the value for [key], or null if not present.
  V? operator [](K key) => value[key];

  /// Returns the current keys in the map.
  Iterable<K> get keys => value.keys;

  /// Returns the current values in the map.
  Iterable<V> get values => value.values;

  /// Returns the current entries in the map.
  Iterable<MapEntry<K, V>> get entries => value.entries;

  /// The version of the snapshot blob this build writes and reads.
  ///
  /// Layout: `version: u8`, `count: uvarint`, then per entry
  /// `keyLen: uvarint`, `key: bytes`, `valueLen: uvarint`, `value: bytes`.
  /// The tags stay out: a snapshot holds the projected map, and the entries
  /// come back tagless.
  static const int _snapshotVersion = 1;

  /// Returns the current state for snapshotting as a binary blob.
  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    final entries = value;
    UVarint.write(entries.length, out);
    for (final entry in entries.entries) {
      UVarint.writeBytes(_keyCodec.encode(entry.key), out);
      UVarint.writeBytes(_valueCodec.encode(entry.value), out);
    }
    return out.toBytes();
  }

  /// Computes the tag state by replaying the history.
  ORMapState<K, V> _computeState() {
    final state = ORMapState<K, V>._(
      live: <K, Set<ORMapEntry<V>>>{},
      all: <K, Set<ORMapEntry<V>>>{},
      snapshotOnly: <K, V>{},
      tombstones: <OperationId>{},
    );

    final snap = lastSnapshot();

    // Seed from snapshot:
    // If a prior snapshot contained key-value pairs for this handler,
    // we treat them as present without tags (snapshot-only) until changes
    // say otherwise. The snapshot is a length-prefixed sequence of
    // (key, value) pairs encoded via [_keyCodec] and [_valueCodec].
    if (snap != null) {
      var offset = SnapshotBlob.read(
        snap,
        version: _snapshotVersion,
        name: 'OR-map',
      );
      final countRec = UVarint.read(snap, offset: offset);
      offset = countRec.nextOffset;
      for (var i = 0; i < countRec.value; i += 1) {
        final keyRecord = UVarint.readBytes(
          snap,
          offset: offset,
          what: 'OR-map snapshot key',
        );
        final key = _keyCodec.decode(keyRecord.value);
        offset = keyRecord.nextOffset;

        final valueRecord = UVarint.readBytes(
          snap,
          offset: offset,
          what: 'OR-map snapshot value',
        );
        state._snapshotOnly[key] = _valueCodec.decode(valueRecord.value);
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

  /// Applies a single operation to the tag state
  void _applyOperationToTagState({
    required ORMapState<K, V> state,
    required Operation operation,
  }) {
    if (operation is _ORMapPutOperation<K, V>) {
      _tagStatePut(
        state: state,
        operation: operation,
      );
    } else if (operation is _ORMapRemoveOperation<K, V>) {
      _tagStateRemove(
        state: state,
        operation: operation,
      );
    }
  }

  void _tagStatePut({
    required ORMapState<K, V> state,
    required _ORMapPutOperation<K, V> operation,
  }) {
    final key = operation.key;
    final value = operation.value;
    // The stamp is there for every put: the handler is stamped, so the
    // document mints one locally and the decode refuses a change without one.
    final tag = operation.stamp!;

    final entry = ORMapEntry<V>(value: value, tag: tag);

    // Register entry in all (seen)
    state._all.putIfAbsent(key, () => <ORMapEntry<V>>{}).add(entry);

    // Add to live if not tomb-stoned yet
    if (!state._tombstones.contains(tag)) {
      state._live.putIfAbsent(key, () => <ORMapEntry<V>>{}).add(entry);
    }

    // A concrete put overrides snapshot-only presence for this key
    state._snapshotOnly.remove(key);
  }

  void _tagStateRemove({
    required ORMapState<K, V> state,
    required _ORMapRemoveOperation<K, V> operation,
  }) {
    final key = operation.key;

    // Remove-all semantics: remove snapshot-only presence for this key
    if (operation.removeAll) {
      state._snapshotOnly.remove(key);
    }

    // Tombstone all provided tags for the key
    state._tombstones.addAll(operation.tags);

    // Remove entries with tomb-stoned tags from live
    final liveForKey = state._live[key];
    if (liveForKey != null) {
      liveForKey.removeWhere((entry) => operation.tags.contains(entry.tag));
      if (liveForKey.isEmpty) {
        state._live.remove(key);
      }
    }
  }

  /// The key an operation is about, or `null` for a kind that is about no
  /// single key.
  ///
  /// A record rather than a bare `K?`, for the same reason [_liveEntryOf]
  /// returns one: a map keyed by a nullable type can hold `null`, and "this
  /// operation is about `null`" must not read as "this operation is about
  /// nothing".
  (K,)? _targetKey(Operation operation) {
    if (operation is _ORMapPutOperation<K, V>) {
      return (operation.key,);
    }
    if (operation is _ORMapRemoveOperation<K, V>) {
      return (operation.key,);
    }
    return null;
  }

  /// What [key] holds right now, without building the whole map.
  ///
  /// `null` when the key is not there. The live entry with the highest tag
  /// wins, exactly as [ORMapState._state] resolves it.
  (V,)? _liveEntryOf(ORMapState<K, V> state, K key) {
    final entries = state._live[key];
    if (entries != null && entries.isNotEmpty) {
      ORMapEntry<V>? winning;
      for (final entry in entries) {
        if (winning == null || entry.tag.compareTo(winning.tag) > 0) {
          winning = entry;
        }
      }
      return (winning!.value,);
    }
    if (state._snapshotOnly.containsKey(key)) {
      return (state._snapshotOnly[key] as V,);
    }
    return null;
  }

  /// What [key] did, given what it held before and after.
  MapDelta<K, V> _entryDelta(K key, (V,)? before, (V,)? after) {
    if (after != null) {
      if (before != null && before.$1 == after.$1) {
        return MapDelta<K, V>.empty();
      }
      return MapDelta<K, V>({
        key: MapEntrySet<V>(value: after.$1, previous: before?.$1),
      });
    }
    if (before != null) {
      return MapDelta<K, V>({
        key: MapEntryRemoved<V>(previous: before.$1),
      });
    }
    return MapDelta<K, V>.empty();
  }

  /// The stamp of a `put` is the tag it wrote, so an undo takes back that one
  /// tag and the entry that held the key before wins again on its own.
  @override
  bool get invertible => true;

  /// What an inverse `put` brings back, so [prepareInverse] can follow the tag
  /// it ends up written under. Weakly keyed: it dies with the operation.
  final Expando<Set<OperationId>> _restoredTags = Expando<Set<OperationId>>();

  @override
  List<Operation> invert(Operation operation) {
    final state = _cachedOrComputedState();

    if (operation is _ORMapPutOperation<K, V>) {
      final key = operation.key;

      // This put may itself be an undo putting the key back. Its stamp is the
      // tag that now stands for the ones it restores.
      final restored = _restoredTags[operation];
      if (restored != null) {
        for (final tag in restored) {
          noteRebuilt(tag, operation.stamp!);
        }
      }
      if (!_hasLiveTag(state, key) && state._snapshotOnly.containsKey(key)) {
        // The key is there through a snapshot that carries no tags, and the
        // put takes that presence away. Taking the new tag back would leave
        // the key absent, so write the old value instead: what anyone can see
        // is the same either way.
        return [
          _ORMapPutOperation<K, V>.fromHandler(
            this,
            key: key,
            value: state._snapshotOnly[key] as V,
          ),
        ];
      }
      // Take back the one tag this put wrote; the entry that held the key
      // before wins again on its own.
      return [
        _ORMapRemoveOperation<K, V>.fromHandler(
          this,
          key: key,
          tags: {operation.stamp!},
        ),
      ];
    }

    if (operation is _ORMapRemoveOperation<K, V>) {
      final key = operation.key;

      // One put per entry this remove takes away, so undoing an earlier put
      // can take back its own. Collapsing them into a single put would leave
      // the key hanging on one tag, and the first undo would drop it.
      //
      // Oldest tag first: the puts are written in this order, so the entry
      // that won before wins again.
      final live = state._live[key];
      final taken = <ORMapEntry<V>>[
        if (live != null)
          for (final entry in live)
            if (operation.tags.contains(entry.tag)) entry,
      ]..sort((a, b) => a.tag.compareTo(b.tag));

      final puts = <Operation>[];
      for (final entry in taken) {
        // The entry comes back under a new tag: a tombstone is forever.
        final put = _ORMapPutOperation<K, V>.fromHandler(
          this,
          key: key,
          value: entry.value,
        );
        _restoredTags[put] = {entry.tag};
        puts.add(put);
      }
      if (puts.isNotEmpty) {
        return puts;
      }

      // No tag changed hands. The remove still takes away a value that comes
      // from a snapshot carrying no tags.
      if (operation.removeAll && state._snapshotOnly.containsKey(key)) {
        return [
          _ORMapPutOperation<K, V>.fromHandler(
            this,
            key: key,
            value: state._snapshotOnly[key] as V,
          ),
        ];
      }
      return const [];
    }

    return const [];
  }

  @override
  Operation prepareInverse(Operation operation) {
    if (!hasRebuiltIdentities || operation is! _ORMapRemoveOperation<K, V>) {
      return operation;
    }
    // Tombstone the whole chain: the tag the inverse names, and every tag that
    // has stood for it since.
    final tags = <OperationId>{
      for (final tag in operation.tags) ...chainOf(tag),
    };
    if (tags.length == operation.tags.length) {
      return operation;
    }
    return _ORMapRemoveOperation<K, V>.fromHandler(
      this,
      key: operation.key,
      tags: tags,
    );
  }

  /// Whether [key] has at least one live entry, so it does not read its value
  /// from the snapshot alone.
  bool _hasLiveTag(ORMapState<K, V> state, K key) {
    final entries = state._live[key];
    return entries != null && entries.isNotEmpty;
  }

  @override
  bool get stateIsOrderIndependent => true;

  @override
  ORMapState<K, V>? incrementCachedState({
    required Operation operation,
    required ORMapState<K, V> state,
    DeltaSink<Object?>? sink,
  }) {
    // The cached state is never exposed by this handler, so it can be
    // mutated in place instead of deep-copied on every operation.
    try {
      // Tag-level again: a put that loses the tag comparison moves the tags
      // but not the key anyone can see. Read the key before and after.
      final target = _targetKey(operation);
      final before = target == null ? null : _liveEntryOf(state, target.$1);

      _applyOperationToTagState(
        state: state,
        operation: operation,
      );

      if (sink != null) {
        sink.add(
          target == null
              ? MapDelta<K, V>.empty()
              : _entryDelta(
                  target.$1,
                  before,
                  _liveEntryOf(state, target.$1),
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
  Map<K, V> applyDelta(Map<K, V> base, MapDelta<K, V> delta) =>
      delta.apply(base);
}

/// State of the [CRDTORMapHandler]
class ORMapState<K, V> {
  /// - [_live]: current non-tomb-stoned entries (value, tag) per key
  /// (key is present if it has at least one live entry)
  /// - [_all]: all entries ever observed per key
  /// (useful for computing default removals)
  /// - [_snapshotOnly]: key-value pairs seeded from snapshot
  /// without any concrete put tags yet
  /// - [_tombstones]: set of tomb-stoned tags observed
  /// so far while replaying history.
  /// - [_state]: the current state of the OR-Map
  ORMapState._({
    required Map<K, Set<ORMapEntry<V>>> live,
    required Map<K, Set<ORMapEntry<V>>> all,
    required Map<K, V> snapshotOnly,
    required Set<OperationId> tombstones,
  })  : _tombstones = tombstones,
        _snapshotOnly = snapshotOnly,
        _all = all,
        _live = live;

  /// Returns all tags for a given key (across all entries)
  Set<OperationId> _allTagsForKey(K key) {
    final allForKey = _all[key];
    if (allForKey == null) {
      return <OperationId>{};
    }
    return allForKey.map((entry) => entry.tag).toSet();
  }

  /// The live entries per key
  final Map<K, Set<ORMapEntry<V>>> _live;

  /// All entries per key
  final Map<K, Set<ORMapEntry<V>>> _all;

  /// Snapshot-only key-value pairs
  final Map<K, V> _snapshotOnly;

  /// The tombstones
  final Set<OperationId> _tombstones;

  /// The state of the OR-Map.
  /// For each key with live entries, we pick the entry with the
  /// highest tag (by HLC, then PeerId) for deterministic conflict resolution.
  Map<K, V> get _state {
    final result = <K, V>{}
      // Add snapshot-only entries
      ..addAll(_snapshotOnly);

    // Override with live entries
    for (final keyEntry in _live.entries) {
      final key = keyEntry.key;
      final entries = keyEntry.value;

      // Find the entry with the highest tag (by HLC, then PeerId)
      ORMapEntry<V>? winningEntry;

      for (final entry in entries) {
        if (winningEntry == null || entry.tag.compareTo(winningEntry.tag) > 0) {
          winningEntry = entry;
        }
      }

      if (winningEntry != null) {
        result[key] = winningEntry.value;
      }
    }

    return result;
  }
}

/// Entry in the OR-Map representing a (value, tag) pair
class ORMapEntry<V> {
  /// Creates an OR-Map entry
  ORMapEntry({
    required this.value,
    required this.tag,
  });

  /// The value of this entry
  final V value;

  /// The unique tag for this entry
  final OperationId tag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ORMapEntry<V> && other.value == value && other.tag == tag;
  }

  late final int _hashCode = Object.hash(value, tag);

  @override
  int get hashCode => _hashCode;
}
