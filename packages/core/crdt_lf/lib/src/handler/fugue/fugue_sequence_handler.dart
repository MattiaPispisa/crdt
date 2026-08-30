import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_cache.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_apply.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';

/// Lazily-resolved state shared by Fugue-based ordered-sequence handlers.
///
/// Wraps a [FugueTree] (the source of truth) and memoizes the public value,
/// so that a batch of mutations resolves it at most once, on the next read.
///
/// `T` is the element type stored in the tree, `V` is the public value type
/// (`String` for text, `List<T>` for a list). The projection from the tree to
/// the public value is provided at construction time.
class FugueState<T, V> {
  /// Creates a state over `tree`, projecting the public value with `project`.
  FugueState(this._tree, this._project);

  final FugueTree<T> _tree;
  final V Function(FugueTree<T> tree) _project;

  V? _cachedValue;

  /// The public value, resolved lazily from the tree.
  V get _value => _cachedValue ??= _project(_tree);

  /// Discards the resolved value after a tree mutation; it is resolved again
  /// lazily on the next read.
  void _markDirty() {
    _cachedValue = null;
  }
}

/// Base for Fugue-backed handlers whose state is an **ordered sequence** of
/// `T` values: a single [FugueTree] plus a pure projection to the public
/// value `V`. `CRDTFugueTextHandler` and `CRDTFugueListHandler` extend it.
///
/// It owns everything those variants have in common on top of [FugueCache]:
/// history replay, snapshot framing, the [delete] operation and the
/// tree-navigation helpers used to build inserts and updates. The counter and
/// the cache lifecycle come from [FugueCache].
///
/// Subclasses provide the element type `T`, the public value type `V` and the
/// concrete state type `S`, plus the extension points that depend on the
/// concrete operation encoding (see the methods grouped under
/// "Extension points").
///
/// ## When NOT to use this
/// This base assumes the visible order equals the live-node traversal order of
/// the tree (so `findNodeAtPosition` maps a visible index to a node). A handler
/// whose visible order is decoupled from the tree — e.g. a movable list, where
/// an element's position is the result of its latest move — must not extend it;
/// it should mix in [FugueCache] directly and own its own navigation.
///
/// ## Note on `T`
/// `T` must be non-nullable. The Fugue tree keeps `null` for the root, the
/// one node that stands for no element, and a stored `null` would look the
/// same.
abstract base class FugueSequenceHandler<T, V, S extends FugueState<T, V>>
    extends Handler<S> with FugueCache<S>, RebuiltIdentities<FugueElementID> {
  /// Creates a Fugue sequence handler bound to [doc] with the given [id].
  FugueSequenceHandler(super.doc, String id, {super.handlerType}) : _id = id;

  final String _id;

  @override
  String get id => _id;

  /// `update` overwrites an element in place, so it needs a stamp to pick a
  /// winner. `insert` and `delete` do not: element ids are unique, and a
  /// deletion beats everything.
  @override
  late final OperationType updateType = OperationType.update(
    this,
    stamped: true,
  );

  /// Creates an empty state (an empty tree with this handler's projection).
  S createEmptyState();

  /// Applies a single decoded [operation] to [tree].
  ///
  /// [sink] collects what the operation did to the sequence, in the
  /// coordinates it had before. It is `null` on the replay path, which nobody
  /// observes.
  void applyToTree(
    FugueTree<T> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  });

  /// The element ids this peer created in [operation], used to seed the
  /// counter.
  ///
  /// Returns nothing for operations that create no node: `delete` and
  /// `update`, which addresses an element that already exists.
  Iterable<FugueElementID> producedElementIds(Operation operation);

  /// Builds the delete operation for the given [nodeIDs].
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs);

  /// Builds the insert operation that puts [items] between [leftOrigin] and
  /// [rightOrigin], one element per entry.
  Operation buildInsertOperation({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<({FugueElementID id, T value})> items,
  });

  /// Builds the update operation that writes each value of [items] over the
  /// element it names.
  Operation buildUpdateOperation(
    List<({FugueElementID nodeID, T value})> items,
  );

  /// Encodes the [values] of one snapshot run into a single blob.
  ///
  /// The blob carries no count of its own, so an implementation picks any
  /// framing [decodeRun] can undo given the number of values.
  Uint8List encodeRun(List<T> values);

  /// Decodes a run blob holding exactly [length] values, the inverse of
  /// [encodeRun].
  List<T> decodeRun(Uint8List blob, int length);

  @override
  Iterable<FugueElementID> knownElementIds() sync* {
    for (final node in _initialState().nodes) {
      yield node.id;
    }
    for (final op in operations()) {
      yield* producedElementIds(op);
    }
  }

  @override
  S computeState() {
    final state = createEmptyState();

    // Seed from the snapshot, then replay the history.
    final seed = _initialState();
    state._tree.bulkSeed(
      seed.nodes,
      seed.stamps,
      live: seed.live,
    );
    for (final operation in operations()) {
      applyToTree(state._tree, operation);
    }

    // The projections are resolved lazily on the first read.
    return state;
  }

  @override
  bool get stateIsOrderIndependent => true;

  @override
  void applyOperation(
    S state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    // The tree is mutated in place; the projections are resolved lazily on
    // the next read instead of after every operation.
    applyToTree(state._tree, operation, sink: sink);
    state._markDirty();
  }

  /// The current value, computed from changes and snapshot.
  V get value => cachedOrComputedState()._value;

  /// The number of live elements, in `O(1)`.
  int get elementCount => cachedOrComputedState()._tree.liveLength;

  /// Deletes [count] elements starting at [index].
  ///
  /// A range that runs off the end deletes what it reaches. A negative [index]
  /// starts at `0`, and the slots before it come off [count].
  void delete(int index, int count) {
    final state = cachedOrComputedState();

    final from = index < 0 ? 0 : index;
    final take = index < 0 ? count + index : count;

    final targets = state._tree.findNodesInRange(from, take);
    if (targets.isEmpty) {
      return;
    }

    doc.registerOperation(buildDeleteOperation(targets));
  }

  /// The left origin for an insertion at [index]: the root id for index `0`,
  /// otherwise the node currently at `index - 1`.
  FugueElementID originBefore(int index) {
    if (index == 0) {
      return FugueElementID.nullID();
    }
    return cachedOrComputedState()._tree.findNodeAtPosition(index - 1);
  }

  /// The node that follows [id] in traversal order.
  FugueElementID nodeAfter(FugueElementID id) {
    return cachedOrComputedState()._tree.findNextNode(id);
  }

  /// The node currently at [index], or a null id if out of range.
  FugueElementID nodeAt(int index) {
    return cachedOrComputedState()._tree.findNodeAtPosition(index);
  }

  /// A stable anchor for a caret/cursor sitting at [index]: the id of the
  /// element currently at `index - 1` (a null id for the sequence start).
  ///
  /// Resolve it back to a current index with [indexOfStablePosition];
  ///
  /// An [index] past the end anchors to the last element. `O(√n)`.
  FugueElementID stablePositionAt(int index) {
    if (index <= 0) {
      return FugueElementID.nullID();
    }
    final state = cachedOrComputedState();
    final liveCount = state._tree.liveLength;
    if (liveCount == 0) {
      return FugueElementID.nullID();
    }
    final anchor = index < liveCount ? index - 1 : liveCount - 1;
    return state._tree.findNodeAtPosition(anchor);
  }

  /// The current index of a caret anchored at [position] (obtained from
  /// [stablePositionAt], possibly on another peer): the position right after
  /// the anchored element, wherever it sits now.
  ///
  /// If the element has been deleted the caret resolves to where the element
  /// used to be. Returns `null` for an element unknown to this document
  int? indexOfStablePosition(FugueElementID position) {
    if (position.isNull) {
      return 0;
    }
    return cachedOrComputedState()._tree.liveIndexAfter(position);
  }

  /// Every operation of this handler names element ids, and a deleted element
  /// keeps its value, so all three kinds invert exactly.
  @override
  bool get invertible => true;

  @override
  List<Operation> invert(Operation operation) {
    final tree = cachedOrComputedState()._tree;

    // A cast, not a promotion: the analyzer will not narrow an [Operation] to
    // an interface it merely implements.
    if (operation is FugueSequenceInsert<T>) {
      // Take out the very elements it puts in. Deleting one twice is the same
      // as deleting it once, so a concurrent delete costs nothing.
      final insert = operation as FugueSequenceInsert<T>;
      final nodeIDs = [for (final item in insert.items) item.id];
      return nodeIDs.isEmpty ? const [] : [buildDeleteOperation(nodeIDs)];
    }

    if (operation is FugueSequenceDelete) {
      return _invertDelete(tree, operation as FugueSequenceDelete);
    }

    if (operation is FugueSequenceUpdate<T>) {
      final items = <({FugueElementID nodeID, T value})>[];
      for (final item in (operation as FugueSequenceUpdate<T>).items) {
        final current = tree.valueOf(item.nodeID);
        if (current != null) {
          items.add((nodeID: item.nodeID, value: current));
        }
      }
      return items.isEmpty ? const [] : [buildUpdateOperation(items)];
    }

    return const [];
  }

  /// What an inverse insert puts back, so [prepareInverse] can record the link
  /// only when the undo really runs. Weakly keyed: it dies with the operation.
  final Expando<List<FugueElementID>> _restoredElements =
      Expando<List<FugueElementID>>();

  /// The inserts that put back what [operation] is about to take out.
  ///
  /// One insert per contiguous run, anchored to the **last** element of the
  /// run. That element is a tombstone by the time the undo runs, and a
  /// tombstone is still a node of the tree, so the run lands back where it was
  /// taken from, whatever else has been written around it since.
  ///
  /// A run comes back as **one block**. Text a peer inserted between two
  /// deleted elements while the delete was in flight therefore ends up in
  /// front of the restored block, not inside it.
  ///
  /// The elements come back with new ids: an element that was removed cannot
  /// be brought back to life.
  List<Operation> _invertDelete(
    FugueTree<T> tree,
    FugueSequenceDelete operation,
  ) {
    final inverses = <Operation>[];
    var items = <({FugueElementID was, FugueElementID id, T value})>[];
    var runEnd = FugueElementID.nullID();

    void flush() {
      if (items.isEmpty) {
        return;
      }
      inverses.add(
        buildInsertOperation(
          leftOrigin: runEnd,
          rightOrigin: tree.findNextNode(runEnd),
          items: [for (final item in items) (id: item.id, value: item.value)],
        ),
      );
      _restoredElements[inverses.last] = [for (final item in items) item.was];
      items = <({FugueElementID was, FugueElementID id, T value})>[];
      runEnd = FugueElementID.nullID();
    }

    for (final item in operation.items) {
      // An element that is not there, or is already a tombstone, is not moved
      // by this delete, so nothing puts it back. It breaks the run either way.
      final value = tree.isLive(item.nodeID) ? tree.valueOf(item.nodeID) : null;
      if (value == null) {
        flush();
        continue;
      }
      if (items.isNotEmpty && tree.findNextNode(runEnd) != item.nodeID) {
        flush();
      }
      items.add(
        (
          was: item.nodeID,
          id: FugueElementID(doc.peerId, nextCounter()),
          value: value,
        ),
      );
      runEnd = item.nodeID;
    }
    flush();

    return inverses;
  }

  @override
  Operation prepareInverse(Operation operation) {
    final restored = _restoredElements[operation];
    if (restored != null && operation is FugueSequenceInsert<T>) {
      // The undo is happening: from here on, the elements this puts in stand
      // for the ones it puts back.
      final items = (operation as FugueSequenceInsert<T>).items;
      for (var i = 0; i < restored.length && i < items.length; i += 1) {
        noteRebuilt(restored[i], items[i].id);
      }
      return operation;
    }

    if (!hasRebuiltIdentities) {
      return operation;
    }

    if (operation is FugueSequenceDelete) {
      // Take out the whole chain: the element the inverse names, and every
      // element that has stood for it since. Deleting a tombstone twice costs
      // nothing, so naming them all is safe.
      final items = (operation as FugueSequenceDelete).items;
      final nodeIDs = [
        for (final item in items) ...chainOf(item.nodeID),
      ];
      return nodeIDs.length == items.length
          ? operation
          : buildDeleteOperation(nodeIDs);
    }

    if (operation is FugueSequenceUpdate<T>) {
      // Write over the element that stands for the one the inverse names.
      return buildUpdateOperation([
        for (final item in (operation as FugueSequenceUpdate<T>).items)
          (nodeID: latestOf(item.nodeID), value: item.value),
      ]);
    }

    return operation;
  }

  @override
  Uint8List getSnapshotState() {
    return FugueSnapshot.write<T>(
      tree: cachedOrComputedState()._tree,
      floor: elementIdFloorForSnapshot(),
      encodeRun: encodeRun,
    );
  }

  /// Decodes the snapshot blob for this handler, or an empty seed if there is
  /// no snapshot.
  ///
  /// Also seeds the element id floor from the blob, so counters spent on
  /// elements that were deleted and pruned are never reissued.
  FugueSnapshotData<T> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return FugueSnapshotData<T>(
        nodes: const [],
        stamps: const {},
        live: const [],
        floor: const {},
      );
    }

    final data = FugueSnapshot.read<T>(snapshot, decodeRun: decodeRun);
    seedElementIdFloor(data.floor);
    return data;
  }
}
