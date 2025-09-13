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
  CRDTMapHandler(super.doc, this._id);

  /// The ID of this map in the document
  final String _id;

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
  Map<String, T> get value {
    // Check if the cached state is still valid
    if (cachedState != null) {
      return cachedState!;
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    updateCachedState(state);

    return Map.from(state);
  }

  @override
  Map<String, T> getSnapshotState() {
    return value;
  }

  /// Gets the value associated with the given key
  T? operator [](String key) => value[key];

  /// Computes the current state of the map from the document's changes
  Map<String, T> _computeState() {
    final state = _initialState();

    // Get all changes from the document
    final changes = doc.exportChanges().sorted();

    // Apply changes in order
    final opFactory = _MapOperationFactory<T>(this);

    for (final change in changes) {
      final payload = change.payload;
      final operation = opFactory.fromPayload(payload);

      if (operation != null) {
        _applyOperationToMap(state, operation);
      }
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
    final newState = Map<String, T>.from(state);
    _applyOperationToMap(newState, operation);
    return newState;
  }

  /// Gets the initial state of the map
  Map<String, T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is Map<String, dynamic> &&
        snapshot.values.every((e) => e is T)) {
      return Map.from(snapshot);
    }
    return <String, T>{};
  }

  /// Returns a string representation of this map
  @override
  String toString() {
    return 'CRDTMapHandler($_id, $value)';
  }
}
