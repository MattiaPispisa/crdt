import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';
part 'operation.dart';

/// # CRDT List
///
/// ## Description
/// A CRDTList is a list data structure that uses CRDT
/// for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing elements.
///
/// ## Algorithm
/// Process operations in clock order.
/// Interleaving is handled just using the HLC.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final list = CRDTListHandler<String>(doc, 'list');
/// list..insert(0, 'Hello')..insert(1, 'World')..update(0, 'Hello,')
/// print(list.value.join('')); // Prints "Hello, World"
/// ```
class CRDTListHandler<T> extends Handler<List<T>> {
  /// Creates a new CRDTList with the given document and ID
  CRDTListHandler(super.doc, this._id);

  @override
  late final OperationFactory operationFactory =
      _ListOperationFactory<T>(this).fromPayload;

  /// The ID of this list in the document
  final String _id;

  @override
  String get id => _id;

  /// Inserts an element at the specified index
  void insert(int index, T value) {
    final operation = _ListInsertOperation<T>.fromHandler(
      this,
      index: index,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Deletes elements starting at the specified index
  void delete(int index, int count) {
    final operation = _ListDeleteOperation<T>.fromHandler(
      this,
      index: index,
      count: count,
    );
    doc.registerOperation(operation);
  }

  /// Updates the element at the specified index
  void update(int index, T value) {
    final operation = _ListUpdateOperation<T>.fromHandler(
      this,
      index: index,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Gets the current state of the list
  List<T> get value {
    // Check if the cached state is still valid
    if (cachedState != null) {
      return cachedState!;
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    updateCachedState(state);

    return List.from(state);
  }

  @override
  List<T> getSnapshotState() {
    return value;
  }

  /// Gets the length of the list
  int get length => value.length;

  /// Gets the element at the specified index
  T operator [](int index) => value[index];

  /// Computes the current state of the list from the document's changes
  List<T> _computeState() {
    final state = _initialState();

    for (final operation in operations()) {
      _applyOperationToList(state, operation);
    }

    return state;
  }

  /// Applies a single operation to a list
  void _applyOperationToList(List<T> state, Operation operation) {
    if (operation is _ListInsertOperation<T>) {
      _listInsert(
        state,
        index: operation.index,
        value: operation.value,
      );
    } else if (operation is _ListDeleteOperation) {
      _listDelete(
        state,
        index: operation.index,
        count: operation.count,
      );
    } else if (operation is _ListUpdateOperation<T>) {
      _listUpdate(
        state,
        index: operation.index,
        value: operation.value,
      );
    }
  }

  void _listInsert(
    List<T> state, {
    required int index,
    required T value,
  }) {
    // Insert at the specified index,
    // or at the end if the index is out of bounds
    if (index <= state.length) {
      state.insert(index, value);
    } else {
      state.add(value);
    }
  }

  void _listDelete(
    List<T> state, {
    required int index,
    required int count,
  }) {
    // Delete elements if the index is valid
    if (index < state.length) {
      final actualCount =
          index + count > state.length ? state.length - index : count;
      state.removeRange(index, index + actualCount);
    }
  }

  void _listUpdate(
    List<T> state, {
    required int index,
    required T value,
  }) {
    // Update the element at the specified index
    if (index < state.length) {
      state[index] = value;
    }
  }

  @override
  List<T>? incrementCachedState({
    required Operation operation,
    required List<T> state,
  }) {
    final newState = List<T>.from(state);
    _applyOperationToList(newState, operation);
    return newState;
  }

  /// Gets the initial state of the list
  List<T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is List<dynamic> && snapshot.every((e) => e is T)) {
      return List.from(snapshot);
    }

    return [];
  }

  /// Returns a string representation of this list
  @override
  String toString() {
    return 'CRDTList($_id, $value)';
  }
}
