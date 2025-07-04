import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

/// CRDT Map implementation
///
/// A CRDTMap is a map data structure that uses CRDT
/// for conflict-free collaboration.
/// It provides methods for setting, deleting, and accessing key-value pairs.
class CRDTMapHandler<T> extends Handler<Map<String, T>> {
  /// Creates a new CRDTMap with the given document and ID
  CRDTMapHandler(super.doc, this._id);

  /// The ID of this map in the document
  final String _id;

  @override
  String get id => _id;

  /// Sets a key-value pair in the map
  void set(String key, T value) {
    doc.createChange(
      _MapInsertOperation<T>.fromHandler(
        this,
        key: key,
        value: value,
      ),
    );
    invalidateCache();
  }

  /// Deletes a key from the map
  void delete(String key) {
    doc.createChange(
      _MapDeleteOperation<T>.fromHandler(
        this,
        key: key,
      ),
    );
    invalidateCache();
  }

  /// Updates a key-value pair in the map
  void update(String key, T value) {
    doc.createChange(
      _MapUpdateOperation<T>.fromHandler(
        this,
        key: key,
        value: value,
      ),
    );
    invalidateCache();
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

      if (operation is _MapInsertOperation<T>) {
        state[operation.key] = operation.value;
      } else if (operation is _MapDeleteOperation<T>) {
        state.remove(operation.key);
      } else if (operation is _MapUpdateOperation<T>) {
        state[operation.key] = operation.value;
      }
    }

    return state;
  }

  /// Gets the initial state of the map
  Map<String, T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is Map<String, T>) {
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
