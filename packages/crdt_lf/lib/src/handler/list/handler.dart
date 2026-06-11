import 'dart:typed_data';
import 'package:crdt_lf/crdt_lf.dart';

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
  ///
  /// [valueCodec] is an optional codec for encoding/decoding [T] values to bytes.
  /// Default is [JsonValueCodec].
  CRDTListHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  @override
  late final OperationFactory operationFactory =
      _ListOperationFactory<T>(this).fromBytes;

  /// The ID of this list in the document
  final String _id;

  final ValueCodec<T> _valueCodec;

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
  ///
  /// The returned list is the handler's internal state:
  /// treat it as read-only.
  List<T> get value {
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
    final items = value;
    UVarint.write(items.length, out);
    for (final item in items) {
      final bytes = _valueCodec.encode(item);
      UVarint.write(bytes.length, out);
      out.add(bytes);
    }
    return out.toBytes();
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
    // Mutate the cached state in place instead of copying it on
    // every operation.
    try {
      _applyOperationToList(state, operation);
      return state;
    } catch (_) {
      // The state may be half-mutated: invalidate the cache.
      return null;
    }
  }

  /// Gets the initial state of the list
  List<T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return [];
    }

    var offset = 0;
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;
    final items = <T>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final lenRec = UVarint.read(snapshot, offset: offset);
      offset = lenRec.nextOffset;
      final end = offset + lenRec.value;
      items.add(
        _valueCodec.decode(Uint8List.sublistView(snapshot, offset, end)),
      );
      offset = end;
    }
    return items;
  }

  /// Returns a string representation of this list
  @override
  String toString() {
    return 'CRDTList($_id, $value)';
  }
}
