import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/document.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';
import 'package:crdt_lf/src/utils/set.dart';
part 'operation.dart';

/// CRDT List implementation
///
/// A CRDTList is a list data structure that uses CRDT for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing elements.
class CRDTListHandler<T> extends Handler {
  /// Creates a new CRDTList with the given document and ID
  CRDTListHandler(this._doc, this._id) : super(_doc);

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
    _doc.createChange(
      _ListInsertOperation<T>.fromHandler(
        this,
        index: index,
        value: value,
      ),
    );
    _invalidateCache();
  }

  /// Deletes elements starting at the specified index
  void delete(int index, int count) {
    _doc.createChange(
      _ListDeleteOperation.fromHandler(
        this,
        index: index,
        count: count,
      ),
    );
    _invalidateCache();
  }

  /// Gets the current state of the list
  List<T> get value {
    // Check if the cached state is still valid
    final currentVersion = _doc.version;
    if (_cachedState != null && setEquals(_cachedVersion, currentVersion)) {
      return List.from(_cachedState!);
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    _cachedState = state;
    _cachedVersion = Set.from(currentVersion);

    return List.from(state);
  }

  @override
  List<T> getState() {
    return value;
  }

  /// Gets the length of the list
  int get length => value.length;

  /// Gets the element at the specified index
  T operator [](int index) => value[index];

  /// Computes the current state of the list from the document's changes
  List<T> _computeState() {
    final state = _initialState();

    // Get all changes from the document
    final changes = _doc.exportChanges().sorted();

    // Apply changes in order
    final opFactory = _ListOperationFactory<T>(this);

    for (final change in changes) {
      final payload = change.payload;

      final operation = opFactory.fromPayload(payload);

      if (operation is _ListInsertOperation<T>) {
        final index = operation.index;
        final value = operation.value;

        // Insert at the specified index, or at the end if the index is out of bounds
        if (index <= state.length) {
          state.insert(index, value);
        } else {
          state.add(value);
        }
      } else if (operation is _ListDeleteOperation) {
        final index = operation.index;
        final count = operation.count;

        // Delete elements if the index is valid
        if (index < state.length) {
          final actualCount =
              index + count > state.length ? state.length - index : count;
          state.removeRange(index, index + actualCount);
        }
      }
    }

    return state;
  }

  /// Gets the initial state of the list
  List<T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is List<T>) {
      return snapshot;
    }

    return [];
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
