import 'dart:typed_data';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

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
base class CRDTListHandler<T> extends Handler<List<T>>
    with DeltaProvider<List<T>, SequenceDelta<T>> {
  /// Creates a new CRDTList with the given document and ID
  ///
  /// [valueCodec] is an optional codec for encoding/decoding [T] values to bytes.
  /// Default is [JsonValueCodec].
  CRDTListHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _ListInsertOperation<T>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _ListDeleteOperation<T>.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _ListUpdateOperation<T>.fromBodyBytes(this, body),
  };

  /// The ID of this list in the document
  final String _id;

  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  /// Inserts an element at the specified index
  ///
  /// {@template naive_move}
  /// Do not [delete] + [insert] to move an element
  /// instead use [CRDTFugueMovableListHandler].
  ///
  /// A naive move (delete + insert) can cause a duplicated element.
  ///
  /// ```md
  /// Initial state: [milk, plants, joe]
  /// Peer A:  move(joe → top) ⇒ [joe, milk, plants]
  /// Peer B:  move(joe → top) ⇒ [joe, milk, plants]
  /// Sync:  [joe, joe, milk, plants]   ← duplicated
  /// ```
  /// {@endtemplate}
  void insert(int index, T value) {
    final operation = _ListInsertOperation<T>.fromHandler(
      this,
      index: index,
      value: value,
    );
    doc.registerOperation(operation);
  }

  /// Deletes elements starting at the specified index
  ///
  /// {@macro naive_move}
  ///
  /// Consecutive deletions over adjacent ranges performed inside a
  /// [CRDTDocument.runInTransaction] are compacted into a single delete.
  void delete(int index, int count) {
    final operation = _ListDeleteOperation<T>.fromHandler(
      this,
      index: index,
      count: count,
    );
    doc.registerOperation(operation);
  }

  /// Updates the element at the specified index
  ///
  /// Consecutive updates at the same index performed inside a
  /// [CRDTDocument.runInTransaction] are compacted into a single update
  /// (last write wins).
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
  /// treat it as read-only. `readSynced()` hands back a copy instead, so a
  /// consumer that keeps a projection can hold what it is given.
  @override
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

  /// The version of the snapshot blob this build writes and reads.
  ///
  /// Layout: `version: u8`, `count: uvarint`, then per item
  /// `itemLen: uvarint`, `item: bytes`.
  static const int _snapshotVersion = 1;

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    final items = value;
    UVarint.write(items.length, out);
    for (final item in items) {
      UVarint.writeBytes(_valueCodec.encode(item), out);
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
  ///
  /// [sink] collects what the operation really did, clamping included. It is
  /// `null` on the replay path, which nobody observes.
  void _applyOperationToList(
    List<T> state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (operation is _ListInsertOperation<T>) {
      _listInsert(
        state,
        index: operation.index,
        value: operation.value,
        sink: sink,
      );
    } else if (operation is _ListDeleteOperation) {
      _listDelete(
        state,
        index: operation.index,
        count: operation.count,
        sink: sink,
      );
    } else if (operation is _ListUpdateOperation<T>) {
      _listUpdate(
        state,
        index: operation.index,
        value: operation.value,
        sink: sink,
      );
    } else {
      sink?.add(SequenceDelta<T>.empty());
    }
  }

  void _listInsert(
    List<T> state, {
    required int index,
    required T value,
    DeltaSink<Object?>? sink,
  }) {
    // Insert at the specified index,
    // or at the end if the index is out of bounds
    final at = index <= state.length ? index : state.length;
    state.insert(at, value);
    sink?.add(
      SequenceDelta<T>([
        if (at > 0) SeqRetain<T>(at),
        SeqInsert<T>([value]),
      ]),
    );
  }

  void _listDelete(
    List<T> state, {
    required int index,
    required int count,
    DeltaSink<Object?>? sink,
  }) {
    // Delete elements if the index is valid
    if (index < state.length) {
      final actualCount =
          index + count > state.length ? state.length - index : count;
      state.removeRange(index, index + actualCount);
      sink?.add(
        SequenceDelta<T>([
          if (index > 0) SeqRetain<T>(index),
          if (actualCount > 0) SeqDelete<T>(actualCount),
        ]),
      );
      return;
    }
    sink?.add(SequenceDelta<T>.empty());
  }

  void _listUpdate(
    List<T> state, {
    required int index,
    required T value,
    DeltaSink<Object?>? sink,
  }) {
    // Update the element at the specified index
    if (index < state.length) {
      state[index] = value;
      sink?.add(
        SequenceDelta<T>([
          if (index > 0) SeqRetain<T>(index),
          SeqDelete<T>(1),
          SeqInsert<T>([value]),
        ]),
      );
      return;
    }
    sink?.add(SequenceDelta<T>.empty());
  }

  @override
  Operation? compound(Operation accumulator, Operation current) {
    // Two consecutive deletions over adjacent ranges collapse into one.
    if (accumulator is _ListDeleteOperation<T> &&
        current is _ListDeleteOperation<T>) {
      // Forward delete: both deletions share the same anchor index.
      if (current.index == accumulator.index) {
        return _ListDeleteOperation<T>.fromHandler(
          this,
          index: accumulator.index,
          count: accumulator.count + current.count,
        );
      }
      // Backward delete: the current deletion ends where the accumulated
      // one began.
      if (current.index + current.count == accumulator.index) {
        return _ListDeleteOperation<T>.fromHandler(
          this,
          index: current.index,
          count: accumulator.count + current.count,
        );
      }
    }
    // Two consecutive updates at the same index: the last write wins.
    if (accumulator is _ListUpdateOperation<T> &&
        current is _ListUpdateOperation<T> &&
        current.index == accumulator.index) {
      return _ListUpdateOperation<T>.fromHandler(
        this,
        index: accumulator.index,
        value: current.value,
      );
    }

    return null;
  }

  @override
  List<T>? incrementCachedState({
    required Operation operation,
    required List<T> state,
    DeltaSink<Object?>? sink,
  }) {
    // Mutate the cached state in place instead of copying it on
    // every operation.
    try {
      _applyOperationToList(state, operation, sink: sink);
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

    var offset = SnapshotBlob.read(
      snapshot,
      version: _snapshotVersion,
      name: 'list',
    );
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;
    final items = <T>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final valueRecord = UVarint.readBytes(
        snapshot,
        offset: offset,
        what: 'list snapshot value',
      );
      items.add(_valueCodec.decode(valueRecord.value));
      offset = valueRecord.nextOffset;
    }
    return items;
  }

  /// Returns a string representation of this list
  @override
  List<T> applyDelta(List<T> base, SequenceDelta<T> delta) => delta.apply(base);

  @override
  List<T> copyValue(List<T> value) => List<T>.of(value);

  @override
  String toString() {
    return 'CRDTList($_id, $value)';
  }
}
