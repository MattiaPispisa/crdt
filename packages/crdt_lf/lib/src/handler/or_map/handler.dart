import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

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
class CRDTORMapHandler<K, V> extends Handler<ORMapState<K, V>> {
  /// Creates a new CRDT OR-MapHandler with the given document and ID
  CRDTORMapHandler(super.doc, this._id);

  final String _id;

  @override
  String get id => _id;

  /// Obtains a unique tag for an operation
  ORMapTag _tag() {
    doc.prepareMutation();
    return ORMapTag(
      peerId: doc.peerId,
      hlc: doc.hlc,
    );
  }

  /// Puts [value] for [key] in the map, producing a unique tag.
  ///
  /// If the key already exists, this creates a new tag for the new value,
  /// effectively updating the key's value. The tag is pseudo-causal,
  /// derived from the current document clock and peer id.
  void put(K key, V value) {
    final operation = _ORMapPutOperation<K, V>.fromHandler(
      this,
      key: key,
      value: value,
      tag: _tag(),
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

  /// Returns the current state for snapshotting
  @override
  Map<K, V> getSnapshotState() {
    return value;
  }

  /// Computes the tag state by replaying the history.
  ORMapState<K, V> _computeState() {
    final state = ORMapState<K, V>._(
      live: <K, Set<ORMapEntry<V>>>{},
      all: <K, Set<ORMapEntry<V>>>{},
      snapshotOnly: <K, V>{},
      tombstones: <ORMapTag>{},
    );

    final snap = lastSnapshot();
    final changes = doc.exportChanges().sorted();

    // Seed from snapshot:
    // If a prior snapshot contained key-value pairs for this handler,
    // we treat them as present without tags (snapshot-only) until changes
    // say otherwise.
    if (snap is Map<dynamic, dynamic>) {
      try {
        for (final entry in snap.entries) {
          if (entry.key is K && entry.value is V) {
            state._snapshotOnly[entry.key as K] = entry.value as V;
          }
        }
      } catch (_) {
        // Ignore malformed snapshot
      }
    }

    final opFactory = _ORMapOperationFactory<K, V>(this);

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
    final tag = operation.tag;

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

  @override
  ORMapState<K, V>? incrementCachedState({
    required Operation operation,
    required ORMapState<K, V> state,
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
    required Set<ORMapTag> tombstones,
  })  : _tombstones = tombstones,
        _snapshotOnly = snapshotOnly,
        _all = all,
        _live = live;

  /// Creates a deep copy of the tag state
  ORMapState<K, V> _deepCopy() {
    final live = <K, Set<ORMapEntry<V>>>{
      for (final entry in _live.entries)
        entry.key: Set<ORMapEntry<V>>.from(entry.value),
    };
    final all = <K, Set<ORMapEntry<V>>>{
      for (final entry in _all.entries)
        entry.key: Set<ORMapEntry<V>>.from(entry.value),
    };
    final snapshotOnly = <K, V>{..._snapshotOnly};
    final tombstones = <ORMapTag>{..._tombstones};

    return ORMapState<K, V>._(
      live: live,
      all: all,
      snapshotOnly: snapshotOnly,
      tombstones: tombstones,
    );
  }

  /// Returns all tags for a given key (across all entries)
  Set<ORMapTag> _allTagsForKey(K key) {
    final allForKey = _all[key];
    if (allForKey == null) {
      return <ORMapTag>{};
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
  final Set<ORMapTag> _tombstones;

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
  const ORMapEntry({
    required this.value,
    required this.tag,
  });

  /// The value of this entry
  final V value;

  /// The unique tag for this entry
  final ORMapTag tag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ORMapEntry<V> && other.value == value && other.tag == tag;
  }

  @override
  int get hashCode => Object.hash(value, tag);
}

/// Tag for OR-Map entries, combining HLC and PeerId for proper ordering.
/// Comparison is done first by HLC (causal order),
/// then by PeerId (deterministic).
class ORMapTag implements Comparable<ORMapTag> {
  /// Creates an OR-Map tag
  const ORMapTag({
    required this.hlc,
    required this.peerId,
  });

  /// Parses a tag from string format "peerId@hlc"
  factory ORMapTag.parse(String tag) {
    final parts = tag.split('@');
    if (parts.length != 2) {
      throw FormatException('Invalid tag format: $tag');
    }
    return ORMapTag(
      peerId: PeerId.parse(parts[0]),
      hlc: HybridLogicalClock.parse(parts[1]),
    );
  }

  /// The HLC timestamp
  final HybridLogicalClock hlc;

  /// The peer ID
  final PeerId peerId;

  @override
  int compareTo(ORMapTag other) {
    // First compare by HLC (causal order)
    final hlcComparison = hlc.compareTo(other.hlc);
    if (hlcComparison != 0) {
      return hlcComparison;
    }
    // If HLC is equal, compare by PeerId (deterministic)
    return peerId.compareTo(other.peerId);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ORMapTag && other.hlc == hlc && other.peerId == peerId;
  }

  @override
  int get hashCode => Object.hash(hlc, peerId);

  @override
  String toString() => '$peerId@$hlc';
}
