import '../../document.dart';
import '../../operation/id.dart';
import '../../operation/operation.dart';
import '../../operation/type.dart';
import '../handler.dart';

part 'operation.dart';

/// CRDT List implementation
///
/// A CRDTList is a list data structure that uses CRDT for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing elements.

/// A list data structure that uses CRDT for conflict-free collaboration
class CRDTListHandler<T> extends Handler {
  /// Creates a new CRDTList with the given document and ID
  CRDTListHandler(this._doc, this._id);

  /// The document that owns this list
  final CRDTDocument _doc;

  /// The ID of this list in the document
  final String _id;

  @override
  String get id => _id;

  /// The cached state of the list
  List<T>? _cachedState;

  /// The version at which the cached state was computed
  Set<OperationId>? _cachedVersion;

  /// Inserts an element at the specified index
  void insert(int index, T value) {
    final payload = {
      'type': 'list_insert',
      'id': _id,
      'index': index,
      'value': value,
    };

    _doc.createChange(payload);
    _invalidateCache();
  }

  /// Deletes elements starting at the specified index
  void delete(int index, int count) {
    final payload = {
      'type': 'list_delete',
      'id': _id,
      'index': index,
      'count': count,
    };

    _doc.createChange(payload);
    _invalidateCache();
  }

  /// Gets the current state of the list
  List<T> get value {
    // Check if the cached state is still valid
    final currentVersion = _doc.version;
    if (_cachedState != null && _cachedVersion == currentVersion) {
      return List.from(_cachedState!);
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    _cachedState = state;
    _cachedVersion = Set.from(currentVersion);

    return List.from(state);
  }

  /// Gets the length of the list
  int get length => value.length;

  /// Gets the element at the specified index
  T operator [](int index) => value[index];

  /// Computes the current state of the list from the document's changes
  List<T> _computeState() {
    final state = <T>[];

    // Get all changes from the document
    final changes = _doc.exportChanges();

    // Sort changes by timestamp
    changes
        .sort((a, b) => a.timestamp.toInt64().compareTo(b.timestamp.toInt64()));

    // Apply changes in order
    for (final change in changes) {
      final payload = change.payload;
      if (payload is Map && payload['id'] == _id) {
        if (payload['type'] == 'list_insert') {
          final index = payload['index'] as int;
          final value = payload['value'] as T;

          // Insert at the specified index, or at the end if the index is out of bounds
          if (index <= state.length) {
            state.insert(index, value);
          } else {
            state.add(value);
          }
        } else if (payload['type'] == 'list_delete') {
          final index = payload['index'] as int;
          final count = payload['count'] as int;

          // Delete elements if the index is valid
          if (index < state.length) {
            final actualCount =
                index + count > state.length ? state.length - index : count;
            state.removeRange(index, index + actualCount);
          }
        }
      }
    }

    return state;
  }

  /// Invalidates the cached state
  void _invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
  }

  /// Returns a string representation of this list
  @override
  String toString() {
    return 'CRDTList($_id, ${value.toString()})';
  }
}
