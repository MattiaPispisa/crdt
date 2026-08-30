import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

part 'operation.dart';

/// # CRDT Map
///
/// ## Description
/// A CRDTMap is a map data structure that uses CRDT
/// for conflict-free collaboration.
/// It provides methods for setting, deleting, and accessing key-value pairs.
///
/// ## Algorithm
/// Process operations in clock order.
/// Interleaving is handled just using the HLC.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final map = CRDTMapHandler<String>(doc, 'map');
/// map.set('key1', 'value1');
/// map.set('key2', 'value2');
/// map.delete('key1');
/// map.update('key2', 'value2');
/// print(map.value); // Prints {"key2": "value2"}
/// ```
base class CRDTMapHandler<T> extends Handler<Map<String, T>>
    with DeltaProvider<Map<String, T>, MapDelta<String, T>> {
  /// Creates a new CRDTMap with the given document and ID
  ///
  /// [valueCodec] is an optional codec for encoding/decoding [T] values to bytes.
  /// Default is [JsonValueCodec].
  CRDTMapHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  /// The ID of this map in the document
  final String _id;

  final ValueCodec<T> _valueCodec;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _MapInsertOperation<T>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _MapDeleteOperation<T>.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _MapUpdateOperation<T>.fromBodyBytes(this, body),
  };

  @override
  String get id => _id;

  /// Sets a key-value pair in the map
  ///
  /// Consecutive writes to the **same key** (`set`/`update`/`delete`) performed
  /// inside a [CRDTDocument.runInTransaction] are compacted into a single
  /// operation reflecting the net effect.
  void set(String key, T value) {
    final operation = _MapInsertOperation<T>.fromHandler(
      this,
      key: key,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Deletes a key from the map
  void delete(String key) {
    final operation = _MapDeleteOperation<T>.fromHandler(
      this,
      key: key,
    );
    doc.registerOperation(operation);
  }

  /// Updates a key-value pair in the map
  void update(String key, T value) {
    final operation = _MapUpdateOperation<T>.fromHandler(
      this,
      key: key,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Gets the current state of the map
  ///
  /// The returned map is the handler's internal state:
  /// treat it as read-only. `readSynced()` hands back a copy instead, so a
  /// consumer that keeps a projection can hold what it is given.
  @override
  Map<String, T> get value {
    // Check if the cached state is still valid
    if (cachedState != null) {
      return cachedState!;
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    updateCachedState(state);

    return state;
  }

  /// The version of the snapshot blob this build writes and reads.
  ///
  /// Layout: `version: u8`, `count: uvarint`, then per entry
  /// `keyLen: uvarint`, `key: utf8`, `valueLen: uvarint`, `value: bytes`.
  static const int _snapshotVersion = 1;

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    final entries = value;
    UVarint.write(entries.length, out);
    for (final entry in entries.entries) {
      UVarint.writeString(entry.key, out);
      UVarint.writeBytes(_valueCodec.encode(entry.value), out);
    }
    return out.toBytes();
  }

  /// Gets the value associated with the given key
  T? operator [](String key) => value[key];

  /// Computes the current state of the map from the document's changes
  Map<String, T> _computeState() {
    final state = _initialState();

    // Get all changes from the document
    for (final operation in operations()) {
      _applyOperationToMap(state, operation);
    }

    return state;
  }

  /// Applies a single operation to a map
  ///
  /// [sink] collects what the operation did to the keys anyone can see. It is
  /// `null` on the replay path, which nobody observes.
  void _applyOperationToMap(
    Map<String, T> state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (operation is _MapInsertOperation<T>) {
      final before = _entryBefore(state, operation.key, sink);
      _mapInsert(state, key: operation.key, value: operation.value);
      sink?.add(
        MapDelta<String, T>({
          operation.key: MapEntrySet<T>(
            value: operation.value,
            previous: before?.$1,
          ),
        }),
      );
    } else if (operation is _MapDeleteOperation<T>) {
      final before = _entryBefore(state, operation.key, sink);
      _mapDelete(state, key: operation.key);
      sink?.add(
        before == null
            ? MapDelta<String, T>.empty()
            : MapDelta<String, T>({
                operation.key: MapEntryRemoved<T>(previous: before.$1),
              }),
      );
    } else if (operation is _MapUpdateOperation<T>) {
      final before = _entryBefore(state, operation.key, sink);
      _mapUpdate(state, key: operation.key, value: operation.value);
      // An update of a key that is not there does nothing, so it must not
      // report a phantom entry.
      sink?.add(
        before == null
            ? MapDelta<String, T>.empty()
            : MapDelta<String, T>({
                operation.key: MapEntrySet<T>(
                  value: operation.value,
                  previous: before.$1,
                ),
              }),
      );
    } else {
      sink?.add(MapDelta<String, T>.empty());
    }
  }

  /// What [key] holds before the operation writes, or `null` when the map does
  /// not have it — and `null` too when [sink] is `null`, because then nobody
  /// asked and the two lookups would be thrown away.
  ///
  /// A record and not a bare `T?`: for a map of a nullable type a key holding
  /// `null` is still a key, and removing it is still a move.
  static (T,)? _entryBefore<T>(
    Map<String, T> state,
    String key,
    DeltaSink<Object?>? sink,
  ) {
    if (sink == null || !state.containsKey(key)) {
      return null;
    }
    return (state[key] as T,);
  }

  void _mapInsert(
    Map<String, T> state, {
    required String key,
    required T value,
  }) {
    state[key] = value;
  }

  void _mapDelete(
    Map<String, T> state, {
    required String key,
  }) {
    state.remove(key);
  }

  void _mapUpdate(
    Map<String, T> state, {
    required String key,
    required T value,
  }) {
    if (state.containsKey(key)) {
      state.update(key, (_) => value);
    }
  }

  /// Every operation of this handler names a key, and the value that key holds
  /// is right there in the state, so all three kinds invert exactly.
  @override
  bool get invertible => true;

  @override
  List<Operation> invert(Operation operation) {
    final key = _keyOf(operation);
    if (key == null) {
      return const [];
    }

    // `containsKey` and not a null check: for a map of a nullable type a key
    // holding `null` is still a key, and putting it back is still a move.
    final state = value;
    if (!state.containsKey(key)) {
      // The key is not there yet. Only `set` can have put it there, and
      // removing it again is what undoes that.
      return operation is _MapInsertOperation<T>
          ? [_MapDeleteOperation<T>.fromHandler(this, key: key)]
          : const [];
    }

    final previous = state[key] as T;
    if (operation is _MapUpdateOperation<T>) {
      // Stay an update: `set` would also recreate a key a concurrent delete
      // took away in the meantime.
      return [
        _MapUpdateOperation<T>.fromHandler(this, key: key, value: previous),
      ];
    }
    if (operation is _MapInsertOperation<T> ||
        operation is _MapDeleteOperation<T>) {
      return [
        _MapInsertOperation<T>.fromHandler(this, key: key, value: previous),
      ];
    }
    return const [];
  }

  @override
  Operation? compound(Operation accumulator, Operation current) {
    final accKey = _keyOf(accumulator);
    final curKey = _keyOf(current);
    // Only writes to the same key can be collapsed.
    if (accKey == null || curKey == null || accKey != curKey) {
      return null;
    }

    // The current op deletes the key: whatever came before, the key ends up
    // absent, so a single delete is equivalent.
    if (current is _MapDeleteOperation<T>) {
      return _MapDeleteOperation<T>.fromHandler(this, key: accKey);
    }

    // The current op is a `set` (insert): it unconditionally establishes the
    // value regardless of what came before.
    if (current is _MapInsertOperation<T>) {
      return _MapInsertOperation<T>.fromHandler(
        this,
        key: accKey,
        value: current.value,
      );
    }

    // The current op is an `update`.
    final currentValue = (current as _MapUpdateOperation<T>).value;
    // set + update: the set forces the key to exist, so the update always
    // applies → equivalent to a single `set` with the updated value.
    if (accumulator is _MapInsertOperation<T>) {
      return _MapInsertOperation<T>.fromHandler(
        this,
        key: accKey,
        value: currentValue,
      );
    }
    // delete + update: the delete removes the key, so the update is a no-op →
    // equivalent to a single delete.
    if (accumulator is _MapDeleteOperation<T>) {
      return _MapDeleteOperation<T>.fromHandler(this, key: accKey);
    }
    // update + update: the last write wins, but only if the key already exists
    // → keep it an `update`.
    return _MapUpdateOperation<T>.fromHandler(
      this,
      key: accKey,
      value: currentValue,
    );
  }

  /// Returns the key targeted by [operation] if it is one of this handler's
  /// operations, or `null` otherwise.
  String? _keyOf(Operation operation) {
    if (operation is _MapInsertOperation<T>) {
      return operation.key;
    }
    if (operation is _MapUpdateOperation<T>) {
      return operation.key;
    }
    if (operation is _MapDeleteOperation<T>) {
      return operation.key;
    }
    return null;
  }

  @override
  Map<String, T>? incrementCachedState({
    required Operation operation,
    required Map<String, T> state,
    DeltaSink<Object?>? sink,
  }) {
    // Mutate the cached state in place instead of copying it on
    // every operation.
    try {
      _applyOperationToMap(state, operation, sink: sink);
      return state;
    } catch (_) {
      // The state may be half-mutated: invalidate the cache.
      return null;
    }
  }

  /// Gets the initial state of the map
  Map<String, T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return <String, T>{};
    }

    var offset = SnapshotBlob.read(
      snapshot,
      version: _snapshotVersion,
      name: 'map',
    );
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;
    final state = <String, T>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final keyRecord = UVarint.readString(
        snapshot,
        offset: offset,
        what: 'map snapshot key',
      );
      offset = keyRecord.nextOffset;

      final valueRecord = UVarint.readBytes(
        snapshot,
        offset: offset,
        what: 'map snapshot value',
      );
      state[keyRecord.value] = _valueCodec.decode(valueRecord.value);
      offset = valueRecord.nextOffset;
    }
    return state;
  }

  @override
  Map<String, T> applyDelta(Map<String, T> base, MapDelta<String, T> delta) =>
      delta.apply(base);

  @override
  Map<String, T> copyValue(Map<String, T> value) => Map<String, T>.of(value);

  /// Returns a string representation of this map
  @override
  String toString() {
    return 'CRDTMapHandler($_id, $value)';
  }
}
