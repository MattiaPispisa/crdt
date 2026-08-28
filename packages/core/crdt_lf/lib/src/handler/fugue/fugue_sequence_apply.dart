import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_delta.dart';

/// One element a Fugue sequence insert puts in.
abstract interface class FugueInsertItem<T> {
  /// The id the element is given in the tree.
  FugueElementID get id;

  /// What the element holds.
  T get value;
}

/// One element a Fugue sequence delete takes out.
abstract interface class FugueDeleteItem {
  /// The element to remove.
  FugueElementID get nodeID;
}

/// One element a Fugue sequence update writes over.
abstract interface class FugueUpdateItem<T> implements FugueDeleteItem {
  /// What the element should hold.
  T get value;
}

/// An operation that puts a contiguous chain of elements into the tree.
abstract interface class FugueSequenceInsert<T> {
  /// The element the chain goes after.
  FugueElementID get leftOrigin;

  /// The element the chain goes before.
  FugueElementID get rightOrigin;

  /// The elements, in order.
  List<FugueInsertItem<T>> get items;
}

/// An operation that turns elements into tombstones.
abstract interface class FugueSequenceDelete {
  /// The elements to remove.
  List<FugueDeleteItem> get items;
}

/// An operation that writes over elements, last writer wins.
abstract interface class FugueSequenceUpdate<T> {
  /// The elements to write over.
  List<FugueUpdateItem<T>> get items;
}

/// Applies one Fugue sequence operation to [tree] and reports what it did.
///
/// The Fugue text and list handlers differ in what an element holds and in
/// nothing else here, so the tree work and the delta that describes it are
/// written once. Each handler declares its own operation classes — they carry
/// their own wire format — and lets them answer the interfaces above.
///
/// [sink] is `null` whenever nobody is watching, and then no delta is built.
///
/// Returns `false` for an operation this does not recognise, so the caller can
/// decide what an unknown kind means.
bool applyFugueSequenceOperation<T>(
  FugueTree<T> tree,
  Operation operation, {
  DeltaSink<Object?>? sink,
}) {
  // A cast, not a promotion: the analyzer will not narrow an [Operation] to
  // an interface it merely implements.
  if (operation is FugueSequenceInsert<T>) {
    final insert = operation as FugueSequenceInsert<T>;
    final items = insert.items;
    tree.iterableInsertChain(
      leftOrigin: insert.leftOrigin,
      rightOrigin: insert.rightOrigin,
      nodes: items.map(
        (item) => FugueValueNode<T>(id: item.id, value: item.value),
      ),
    );
    if (sink != null && items.isNotEmpty) {
      sink.add(
        fugueInsertDelta<T>(
          tree,
          items.first.id,
          items.map((item) => item.value).toList(),
        ),
      );
    }
    return true;
  }

  if (operation is FugueSequenceDelete) {
    final items = (operation as FugueSequenceDelete).items;
    // The places have to be read while the elements are still there.
    final places = sink == null
        ? const <int>[]
        : fugueLivePositions<T>(tree, items.map((item) => item.nodeID));
    for (final item in items) {
      tree.delete(item.nodeID);
    }
    sink?.add(fugueDeleteDelta<T>(places));
    return true;
  }

  if (operation is FugueSequenceUpdate<T>) {
    final winners = <(FugueElementID, T)>[];
    for (final item in (operation as FugueSequenceUpdate<T>).items) {
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
    return true;
  }

  return false;
}
