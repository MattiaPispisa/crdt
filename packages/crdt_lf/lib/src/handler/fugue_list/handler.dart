import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';

part 'operation.dart';

/// # CRDT List with Fugue implementation
///
/// ## Description
/// A CRDTFugueList is a list data structure that uses the Fugue algorithm
/// ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text
/// Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving.
///
/// It is the list counterpart of [CRDTFugueTextHandler]: same conflict
/// resolution, but it stores arbitrary values `T` instead of characters.
/// Compared to [CRDTListHandler] (which orders concurrent edits using the
/// HLC only), Fugue minimizes interleaving when two peers edit the same
/// region concurrently.
///
/// ## Note on `T`
/// The Fugue tree uses a `null` value to mark a deleted element, so `T`
/// must be non-nullable: a stored `null` would be indistinguishable from a
/// deletion. Use the matching [ValueCodec] for non-JSON values.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final list = CRDTFugueListHandler<String>(doc, 'list');
/// list..insert(0, 'Hello')..insert(1, 'World');
/// print(list.value); // Prints ['Hello', 'World']
/// ```
class CRDTFugueListHandler<T>
    extends FugueSequenceHandler<T, List<T>, FugueListState<T>> {
  /// Creates a new CRDTFugueList with the given document and ID
  ///
  /// [valueCodec] is an optional codec for encoding/decoding [T] values to
  /// bytes. Default is [JsonValueCodec].
  CRDTFugueListHandler(
    super.doc,
    super.id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final ValueCodec<T> _valueCodec;

  @override
  late final OperationFactory operationFactory =
      _FugueListOperationFactory<T>(this).fromBytes;

  /// Inserts [value] at position [index]
  ///
  /// {@macro naive_move}
  void insert(int index, T value) {
    insertAll(index, [value]);
  }

  /// Inserts all [values] starting at position [index].
  ///
  /// The inserted run is kept contiguous: a concurrent edit at the same
  /// position never interleaves with these elements (the Fugue property).
  ///
  /// {@macro naive_move}
  void insertAll(int index, Iterable<T> values) {
    final leftOrigin = originBefore(index);
    final rightOrigin = nodeAfter(leftOrigin);

    final items = <_FugueListInsertItem<T>>[];
    for (final value in values) {
      items.add(
        _FugueListInsertItem<T>(
          id: FugueElementID(doc.peerId, nextCounter()),
          value: value,
        ),
      );
    }

    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      _FugueListInsertOperation<T>.fromHandler(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        items: items,
      ),
    );
  }

  /// Updates the element at position [index] with [value]
  void update(int index, T value) {
    final nodeID = nodeAt(index);
    if (nodeID.isNull) {
      return;
    }

    final newNodeID = FugueElementID(doc.peerId, nextCounter());

    doc.registerOperation(
      _FugueListUpdateOperation<T>.fromHandler(
        this,
        items: [
          _FugueListUpdateItem<T>(
            nodeID: nodeID,
            newNodeID: newNodeID,
            value: value,
          ),
        ],
      ),
    );
  }

  /// Gets the length of the list
  int get length => value.length;

  /// Gets the element at the specified index
  T operator [](int index) => value[index];

  @override
  FugueListState<T> createEmptyState() => FugueListState<T>.empty();

  @override
  void applyToTree(FugueTree<T> tree, Operation operation) {
    if (operation is _FugueListInsertOperation<T>) {
      tree.iterableInsertChain(
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
        nodes: operation.items.map(
          (item) => FugueValueNode<T>(id: item.id, value: item.value),
        ),
      );
    } else if (operation is _FugueListDeleteOperation<T>) {
      for (final item in operation.items) {
        tree.delete(item.nodeID);
      }
    } else if (operation is _FugueListUpdateOperation<T>) {
      for (final item in operation.items) {
        tree.update(
          nodeID: item.nodeID,
          newID: item.newNodeID,
          newValue: item.value,
        );
      }
    }
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is _FugueListInsertOperation<T>) {
      for (final item in operation.items) {
        yield item.id;
      }
    } else if (operation is _FugueListUpdateOperation<T>) {
      for (final item in operation.items) {
        yield item.newNodeID;
      }
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return _FugueListDeleteOperation<T>.fromHandler(
      this,
      items: nodeIDs.map((id) => _FugueListDeleteItem(nodeID: id)).toList(),
    );
  }

  @override
  Uint8List encodeValue(T value) => _valueCodec.encode(value);

  @override
  T decodeValue(Uint8List bytes) => _valueCodec.decode(bytes);

  /// Returns a string representation of this handler
  @override
  String toString() {
    return 'CRDTFugueList($id, $value)';
  }
}

/// State of the [CRDTFugueListHandler]: the list of all live node values.
class FugueListState<T> extends FugueState<T, List<T>> {
  /// Creates a list state over [tree].
  FugueListState(FugueTree<T> tree) : super(tree, _collect);

  /// Creates an empty list state.
  factory FugueListState.empty() {
    return FugueListState(FugueTree<T>.empty());
  }

  static List<T> _collect<T>(FugueTree<T> tree) => tree.values();
}
