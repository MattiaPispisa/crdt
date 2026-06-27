import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

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
class CRDTMapHandler<T> extends Handler<Map<String, T>> {
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
  late final OperationFactory operationFactory =
      _MapOperationFactory<T>(this).fromBytes;

  @override
  String get id => _id;

  /// Sets a key-value pair in the map
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
  /// treat it as read-only.
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

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false);
    final entries = value;
    UVarint.write(entries.length, out);
    for (final entry in entries.entries) {
      final keyBytes = utf8.encode(entry.key);
      UVarint.write(keyBytes.length, out);
      out.add(keyBytes);

      final valueBytes = _valueCodec.encode(entry.value);
      UVarint.write(valueBytes.length, out);
      out.add(valueBytes);
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
  void _applyOperationToMap(Map<String, T> state, Operation operation) {
    if (operation is _MapInsertOperation<T>) {
      _mapInsert(state, key: operation.key, value: operation.value);
    } else if (operation is _MapDeleteOperation<T>) {
      _mapDelete(state, key: operation.key);
    } else if (operation is _MapUpdateOperation<T>) {
      _mapUpdate(state, key: operation.key, value: operation.value);
    }
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

  @override
  Map<String, T>? incrementCachedState({
    required Operation operation,
    required Map<String, T> state,
  }) {
    // Mutate the cached state in place instead of copying it on
    // every operation.
    try {
      _applyOperationToMap(state, operation);
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

    var offset = 0;
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;
    final state = <String, T>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final keyLenRec = UVarint.read(snapshot, offset: offset);
      offset = keyLenRec.nextOffset;
      final keyEnd = offset + keyLenRec.value;
      final key = utf8.decode(Uint8List.sublistView(snapshot, offset, keyEnd));
      offset = keyEnd;

      final valLenRec = UVarint.read(snapshot, offset: offset);
      offset = valLenRec.nextOffset;
      final valEnd = offset + valLenRec.value;
      state[key] = _valueCodec.decode(
        Uint8List.sublistView(snapshot, offset, valEnd),
      );
      offset = valEnd;
    }
    return state;
  }

  /// Returns a string representation of this map
  @override
  String toString() {
    return 'CRDTMapHandler($_id, $value)';
  }
}
