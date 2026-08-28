import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_delta.dart';
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
base class CRDTFugueListHandler<T>
    extends FugueSequenceHandler<T, List<T>, FugueListState<T>>
    with DeltaProvider<List<T>, SequenceDelta<T>> {
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
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _FugueListInsertOperation<T>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _FugueListDeleteOperation<T>.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _FugueListUpdateOperation<T>.fromBodyBytes(this, body),
  };

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

  /// Overwrites the element at position [index] with [value], keeping the
  /// identity of that element.
  ///
  /// Two peers updating the same element converge on one of the two values
  /// instead of keeping both, anchors taken with [stablePositionAt] keep
  /// resolving, and nothing is added to the tree. An update loses against a
  /// concurrent deletion of the same element, and does nothing when [index]
  /// is out of range.
  void update(int index, T value) {
    final nodeID = nodeAt(index);
    if (nodeID.isNull) {
      return;
    }

    doc.registerOperation(
      _FugueListUpdateOperation<T>.fromHandler(
        this,
        items: [_FugueListUpdateItem<T>(nodeID: nodeID, value: value)],
      ),
    );
  }

  /// Gets the length of the list, in `O(1)`.
  int get length => elementCount;

  /// Gets the element at the specified index
  T operator [](int index) => value[index];

  @override
  FugueListState<T> createEmptyState() => FugueListState<T>.empty();

  @override
  void applyToTree(
    FugueTree<T> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (operation is _FugueListInsertOperation<T>) {
      tree.iterableInsertChain(
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
        nodes: operation.items.map(
          (item) => FugueValueNode<T>(id: item.id, value: item.value),
        ),
      );
      if (sink != null && operation.items.isNotEmpty) {
        sink.add(
          fugueInsertDelta<T>(
            tree,
            operation.items.first.id,
            operation.items.map((item) => item.value).toList(),
          ),
        );
      }
    } else if (operation is _FugueListDeleteOperation<T>) {
      // The places have to be read while the elements are still there.
      final places = sink == null
          ? const <int>[]
          : fugueLivePositions<T>(
              tree,
              operation.items.map((item) => item.nodeID),
            );
      for (final item in operation.items) {
        tree.delete(item.nodeID);
      }
      sink?.add(fugueDeleteDelta<T>(places));
    } else if (operation is _FugueListUpdateOperation<T>) {
      final winners = <(FugueElementID, T)>[];
      for (final item in operation.items) {
        final won = tree.update(
          nodeID: item.nodeID,
          value: item.value,
          stamp: operation.stamp!,
        );
        // An update that loses the last-writer-wins comparison, or that lands
        // on a tombstone, changes nothing anyone can see.
        if (won && sink != null) {
          winners.add((item.nodeID, item.value));
        }
      }
      sink?.add(fugueUpdateDelta<T>(tree, winners));
    } else {
      sink?.add(SequenceDelta<T>(const []));
    }
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is _FugueListInsertOperation<T>) {
      for (final item in operation.items) {
        yield item.id;
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

  /// Prefixes every value with its length: a [ValueCodec] is free to produce
  /// anything, so nothing else tells one value from the next inside a run.
  @override
  Uint8List encodeRun(List<T> values) {
    final out = BytesBuilder(copy: false);
    for (final value in values) {
      UVarint.writeBytes(_valueCodec.encode(value), out);
    }
    return out.toBytes();
  }

  @override
  List<T> decodeRun(Uint8List blob, int length) {
    final values = <T>[];
    var offset = 0;
    for (var i = 0; i < length; i += 1) {
      final valueRecord = UVarint.readBytes(
        blob,
        offset: offset,
        what: 'Fugue list snapshot value',
      );
      values.add(_valueCodec.decode(valueRecord.value));
      offset = valueRecord.nextOffset;
    }
    return values;
  }

  /// Returns a string representation of this handler
  @override
  String toString() {
    return 'CRDTFugueList($id, $value)';
  }
}

/// State of the [CRDTFugueListHandler]: the list of all live node values.
class FugueListState<T> extends FugueState<T, List<T>> {
  // Private: the tree it wraps is implementation detail, so naming it in a
  // public signature would leak it back out.
  FugueListState._(FugueTree<T> tree) : super(tree, _collect);

  /// Creates an empty list state.
  factory FugueListState.empty() {
    return FugueListState._(FugueTree<T>.empty());
  }

  static List<T> _collect<T>(FugueTree<T> tree) => tree.values();
}
