import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/element_id_floor.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_cache.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_delta.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_restore_runs.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

part 'operation.dart';

/// # CRDT List with Fugue implementation and movable elements
///
/// A list CRDT that supports `insert`, `delete`, `update` **and** an explicit
/// `move` operation that preserves the identity of the moved element across
/// concurrent reorderings (see Kleppmann, [Moving Elements in List CRDTs](https://martin.kleppmann.com/2020/04/27/papoc-list-move.html)).
///
/// Conflict resolution combines:
/// - the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving;
/// - a **last-writer-wins register** on [OperationId] for the value and
///   for the "current position" of each element. Concurrent moves of the same
///   element converge to a single winning destination instead of duplicating
///   the element, and so do concurrent updates of its value.
///
/// ## Identities and positions
/// Every element has a stable [FugueElementID] **identity** assigned at
/// `insert` time (never change). Subsequent `move`/`update`/`delete` operations reference
/// that identity. Each successful `move` allocates a fresh position id that is
/// inserted into the underlying [FugueTree] via the standard Fugue insertion
/// rules; older positions are not removed from the tree but become "orphaned"
/// (their slot is filtered out because the identity now points elsewhere).
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final list = CRDTFugueMovableListHandler<String>(doc, 'todos')
///   ..insert(0, 'buy milk')
///   ..insert(1, 'water plants')
///   ..insert(2, 'phone joe')
///   ..move(2, 0);
/// print(list.value); // ['phone joe', 'buy milk', 'water plants']
/// ```
base class CRDTFugueMovableListHandler<T>
    extends Handler<FugueMovableListState<T>>
    with
        RebuiltIdentities<FugueElementID>,
        FugueCache<FugueMovableListState<T>>,
        DeltaProvider<List<T>, SequenceDelta<T>> {
  /// Creates a movable list handler bound to [doc] with the given [id].
  ///
  /// [valueCodec] is an optional codec for encoding/decoding `T` values to
  /// bytes; default is [JsonValueCodec].
  CRDTFugueMovableListHandler(
    super.doc,
    String id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  })  : _id = id,
        _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final String _id;
  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _MovableListInsertOperation<T>.fromBodyBytes(this, body),
    OperationType.kindMove: (body) =>
        _MovableListMoveOperation<T>.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _MovableListUpdateOperation<T>.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _MovableListDeleteOperation<T>.fromBodyBytes(this, body),
  };

  /// `insert` seeds the two last-writer-wins clocks of an element, and
  /// `move` and `update` race against them, so all three carry a stamp.
  /// `delete` does not: it wins over everything.
  @override
  late final OperationType insertType = OperationType.insert(
    this,
    stamped: true,
  );

  @override
  late final OperationType moveType = OperationType.move(this, stamped: true);

  @override
  late final OperationType updateType = OperationType.update(
    this,
    stamped: true,
  );

  @override
  bool get stateIsOrderIndependent => true;

  /// Returns the current list value.
  @override
  List<T> get value => cachedOrComputedState().value;

  /// Returns the length of the list.
  int get length => value.length;

  /// Returns the element at the given visible [index].
  T operator [](int index) => value[index];

  /// Inserts [value] at the visible position [index].
  void insert(int index, T value) {
    insertAll(index, [value]);
  }

  /// Inserts all [values] starting at the visible position [index].
  ///
  /// The inserted run is kept contiguous: a concurrent edit at the same
  /// position never interleaves with these elements (the Fugue property).
  void insertAll(int index, Iterable<T> values) {
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;

    final leftOrigin =
        index <= 0 ? FugueElementID.nullID() : visible[index - 1];
    final rightOrigin =
        index >= visible.length ? FugueElementID.nullID() : visible[index];

    final items = <_MovableListInsertItem<T>>[];
    for (final value in values) {
      items.add(
        _MovableListInsertItem<T>(
          identityID: FugueElementID(doc.peerId, nextCounter()),
          positionID: FugueElementID(doc.peerId, nextCounter()),
          value: value,
        ),
      );
    }
    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      _MovableListInsertOperation<T>.fromHandler(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        items: items,
      ),
    );
  }

  /// Moves the element currently at visible position [from] so that, after
  /// the move, it appears at visible position [to].
  ///
  /// Indexes are interpreted in the **visible** list (no-op slots are skipped).
  /// Negative `from`, `from` out of range or `from == to` is a no-op.
  ///
  /// Range move is not supported, is an open problem [paper §4: open problem]((https://martin.kleppmann.com/2020/04/27/papoc-list-move.html))
  void move(int from, int to) {
    if (from == to) {
      return;
    }
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;
    if (from < 0 || from >= visible.length) {
      return;
    }

    // Lift the moving slot out and compute origins on the resulting list.
    final movingPosition = visible[from];
    final identityID = _identityForPosition(state, movingPosition);
    if (identityID == null) {
      return;
    }

    final filtered = [...visible]..removeAt(from);
    final clampedTo = to.clamp(0, filtered.length);
    final leftOrigin =
        clampedTo == 0 ? FugueElementID.nullID() : filtered[clampedTo - 1];
    final rightOrigin = clampedTo >= filtered.length
        ? FugueElementID.nullID()
        : filtered[clampedTo];

    final newPositionID = FugueElementID(doc.peerId, nextCounter());

    doc.registerOperation(
      _MovableListMoveOperation<T>.fromHandler(
        this,
        identityID: identityID,
        newPositionID: newPositionID,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      ),
    );
  }

  /// Overwrites the value of the element at visible position [index], keeping
  /// the identity of that element.
  ///
  /// Two peers updating the same element converge on one of the two values
  /// instead of keeping both, and the element keeps its place in the list. An
  /// update loses against a concurrent deletion of the same element, and does
  /// nothing when [index] is out of range.
  ///
  /// The winner is the greater [OperationId]: clock first, peer second.
  void update(int index, T value) {
    final identity = _identityAtVisibleIndex(index);
    if (identity == null) {
      return;
    }

    doc.registerOperation(
      _MovableListUpdateOperation<T>.fromHandler(
        this,
        items: [_MovableListUpdateItem<T>(identityID: identity, value: value)],
      ),
    );
  }

  /// Deletes [count] elements starting at visible position [index].
  void delete(int index, [int count = 1]) {
    if (count <= 0) {
      return;
    }
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;
    if (index < 0 || index >= visible.length) {
      return;
    }

    // Collect identities first, so we delete by identity (stable) instead of
    // by visible index (which would drift as items go away).
    final actualCount =
        index + count > visible.length ? visible.length - index : count;
    final items = <_MovableListDeleteItem>[];
    for (var i = 0; i < actualCount; i += 1) {
      final identity = _identityForPosition(state, visible[index + i]);
      if (identity != null) {
        items.add(_MovableListDeleteItem(identityID: identity));
      }
    }
    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      _MovableListDeleteOperation<T>.fromHandler(
        this,
        items: items,
      ),
    );
  }

  /// Every operation of this handler names identities, and an element keeps
  /// its value once deleted, so all four kinds invert exactly.
  @override
  bool get invertible => true;

  @override
  List<Operation> invert(Operation operation) {
    final state = cachedOrComputedState();

    if (operation is _MovableListInsertOperation<T>) {
      // Take out the very identities it puts in.
      final items = [
        for (final item in operation.items)
          _MovableListDeleteItem(identityID: item.identityID),
      ];
      return items.isEmpty
          ? const []
          : [_MovableListDeleteOperation<T>.fromHandler(this, items: items)];
    }

    if (operation is _MovableListDeleteOperation<T>) {
      return _invertDelete(state, operation);
    }

    if (operation is _MovableListUpdateOperation<T>) {
      final items = <_MovableListUpdateItem<T>>[];
      for (final item in operation.items) {
        final element = state._elements[item.identityID];
        // An update of an element that is gone changes nothing anyone sees.
        if (element != null && !element.deleted) {
          items.add(
            _MovableListUpdateItem<T>(
              identityID: item.identityID,
              value: element.value,
            ),
          );
        }
      }
      return items.isEmpty
          ? const []
          : [_MovableListUpdateOperation<T>.fromHandler(this, items: items)];
    }

    if (operation is _MovableListMoveOperation<T>) {
      final element = state._elements[operation.identityID];
      if (element == null || element.deleted) {
        return const [];
      }
      // Put the identity back beside the slot it holds now. That slot is
      // orphaned by the move, so it is invisible and cannot shift the result.
      final wasAt = element.position;
      return [
        _MovableListMoveOperation<T>.fromHandler(
          this,
          identityID: operation.identityID,
          newPositionID: FugueElementID(doc.peerId, nextCounter()),
          leftOrigin: wasAt,
          rightOrigin: state._tree.findNextNode(wasAt),
        ),
      ];
    }

    return const [];
  }

  /// The inserts that put back what [operation] is about to take out.
  ///
  /// One insert per block, cut by [fugueRestoreRuns] over the **slots** the
  /// elements hold: a slot stays in the tree once its element is deleted, so
  /// the block lands back where it was taken from.
  ///
  /// They come back under new identities: a deleted element cannot be brought
  /// back to life. [prepareInverse] follows them.
  List<Operation> _invertDelete(
    FugueMovableListState<T> state,
    _MovableListDeleteOperation<T> operation,
  ) {
    final runs = fugueRestoreRuns<FugueElementID, T>(
      ids: [for (final item in operation.items) item.identityID],
      // An element that is gone already is not moved by this delete, so
      // nothing puts it back.
      probe: (identityID) {
        final element = state._elements[identityID];
        if (element == null || element.deleted) {
          return null;
        }
        return (anchor: element.position, value: element.value);
      },
      nextNode: state._tree.findNextNode,
    );

    final inverses = <Operation>[];
    for (final run in runs) {
      final insert = _MovableListInsertOperation<T>.fromHandler(
        this,
        leftOrigin: run.leftOrigin,
        rightOrigin: run.rightOrigin,
        items: [
          for (final item in run.items)
            _MovableListInsertItem<T>(
              identityID: FugueElementID(doc.peerId, nextCounter()),
              positionID: FugueElementID(doc.peerId, nextCounter()),
              value: item.value,
            ),
        ],
      );
      noteRestores(insert, [for (final item in run.items) item.was]);
      inverses.add(insert);
    }
    return inverses;
  }

  @override
  Operation prepareInverse(Operation operation) {
    if (operation is _MovableListInsertOperation<T>) {
      // The undo is happening: from here on, the identities this puts in stand
      // for the ones it puts back. Does nothing for an insert that puts
      // nothing back.
      commitRestores(
        operation,
        [for (final item in operation.items) item.identityID],
      );
      return operation;
    }

    if (operation is _MovableListDeleteOperation<T>) {
      // Take out the whole chain: the identity the inverse names, and every
      // identity that has stood for it since. Deleting one twice costs
      // nothing, so naming them all is safe.
      final identityIDs = expandChains(
        [for (final item in operation.items) item.identityID],
      );
      return identityIDs == null
          ? operation
          : _MovableListDeleteOperation<T>.fromHandler(
              this,
              items: [
                for (final identityID in identityIDs)
                  _MovableListDeleteItem(identityID: identityID),
              ],
            );
    }

    if (operation is _MovableListUpdateOperation<T>) {
      final items = operation.items;
      final identityIDs =
          latestOfAll([for (final item in items) item.identityID]);
      return identityIDs == null
          ? operation
          : _MovableListUpdateOperation<T>.fromHandler(
              this,
              items: [
                for (var i = 0; i < items.length; i += 1)
                  _MovableListUpdateItem<T>(
                    identityID: identityIDs[i],
                    value: items[i].value,
                  ),
              ],
            );
    }

    if (operation is _MovableListMoveOperation<T>) {
      final identityID = latestOf(operation.identityID);
      if (identityID == operation.identityID) {
        return operation;
      }
      return _MovableListMoveOperation<T>.fromHandler(
        this,
        identityID: identityID,
        newPositionID: FugueElementID(doc.peerId, nextCounter()),
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
      );
    }

    return operation;
  }

  // --- Internal helpers ---------------------------------------------------

  /// Returns the identity living at the visible [index], or `null` if the
  /// index is out of range.
  FugueElementID? _identityAtVisibleIndex(int index) {
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;
    if (index < 0 || index >= visible.length) {
      return null;
    }
    return _identityForPosition(state, visible[index]);
  }

  /// Resolves the identity currently bound to [positionID] in [state].
  FugueElementID? _identityForPosition(
    FugueMovableListState<T> state,
    FugueElementID positionID,
  ) {
    for (final node in state._tree.nodes()) {
      if (node.id == positionID) {
        return node.value;
      }
    }
    return null;
  }

  @override
  Iterable<FugueElementID> knownElementIds() sync* {
    // Identities and positions allocated for this peer must all be considered
    // when seeding the counter, otherwise we could re-issue an id already in
    // use.
    for (final entry in _seedFromSnapshot().entries) {
      yield entry.key;
      yield entry.value.position;
    }
    for (final op in operations()) {
      if (op is _MovableListInsertOperation<T>) {
        for (final item in op.items) {
          yield item.identityID;
          yield item.positionID;
        }
      } else if (op is _MovableListMoveOperation<T>) {
        yield op.newPositionID;
      }
    }
  }

  @override
  FugueMovableListState<T> computeState() {
    final state = FugueMovableListState<T>.empty();

    // Seed from the snapshot (if any).
    final seeded = _seedFromSnapshot();
    if (seeded.isNotEmpty) {
      // Insert each identity's current slot in traversal order: the snapshot
      // stores them in the order they appeared in the source list.
      for (final entry in seeded.entries) {
        state._elements[entry.key] = entry.value;
      }
      // Slots are inserted as a single Fugue iterable starting at index 0 so
      // the seeded list keeps the same total order as it had in the snapshot.
      state._tree.iterableInsert(
        0,
        seeded.entries.map(
          (e) => FugueValueNode<FugueElementID>(
            id: e.value.position,
            value: e.key,
          ),
        ),
      );
    }

    for (final operation in operations()) {
      applyOperation(state, operation);
    }
    return state;
  }

  @override
  void applyOperation(
    FugueMovableListState<T> state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    // The visible order is a projection of the tree through the identity map,
    // so nothing the tree reports describes it. Reading it either side of the
    // apply is what makes a `move` recognisable as a move instead of a delete
    // and an insert. Two walks, and only for a watched handler.
    // Both come out of one walk, and both survive the [_markDirty] below: the
    // state builds fresh lists rather than editing these, so holding on to
    // them is free.
    final beforeIds = sink == null ? null : state.visibleIdentities();
    final beforeValues = sink == null ? null : state.value;

    if (operation is _MovableListInsertOperation<T>) {
      // Slots into the Fugue tree (handled by the tree's chained insert);
      // identities into the elements map (first-write-wins on (peer, counter),
      // since counters are unique per peer).
      state._tree.iterableInsertChain(
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
        nodes: operation.items.map(
          (item) => FugueValueNode<FugueElementID>(
            id: item.positionID,
            value: item.identityID,
          ),
        ),
      );
      for (final item in operation.items) {
        state._elements.putIfAbsent(
          item.identityID,
          () => _MovableElement<T>(
            value: item.value,
            // The insert's own stamp, not a zero clock: any later move or
            // update has to have observed this insert, so it always carries a
            // greater stamp. Seeding with a real one keeps the peer in the
            // record, which is what settles a tie.
            valueStamp: operation.stamp!,
            position: item.positionID,
            positionStamp: operation.stamp!,
            deleted: false,
          ),
        );
      }
    } else if (operation is _MovableListMoveOperation<T>) {
      state._tree.insert(
        newID: operation.newPositionID,
        value: operation.identityID,
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
      );
      final element = state._elements[operation.identityID];
      if (element != null) {
        // `compareTo`, not `happenedAfter`: two moves sharing a clock are
        // ordered by peer instead of leaving both sides refusing to move,
        // which used to make the winner depend on the arrival order.
        if (operation.stamp!.compareTo(element.positionStamp) > 0) {
          element
            ..position = operation.newPositionID
            ..positionStamp = operation.stamp!;
        }
      }
    } else if (operation is _MovableListUpdateOperation<T>) {
      for (final item in operation.items) {
        final element = state._elements[item.identityID];
        if (element != null) {
          // Last writer wins, with the peer settling an identical clock.
          if (operation.stamp!.compareTo(element.valueStamp) > 0) {
            element
              ..value = item.value
              ..valueStamp = operation.stamp!;
          }
        }
      }
    } else if (operation is _MovableListDeleteOperation<T>) {
      for (final item in operation.items) {
        final element = state._elements[item.identityID];
        if (element != null) {
          element.deleted = true;
        }
      }
    }
    state._markDirty();

    if (sink != null) {
      sink.add(
        _deltaOf(
          state,
          operation,
          beforeIds: beforeIds!,
          beforeValues: beforeValues!,
        ),
      );
    }
  }

  /// What [operation] did to the list anyone can see.
  ///
  /// Derived from the visible order either side of the apply, not from the
  /// tree: a `move` leaves the old slot in place and puts a new one in, and a
  /// `delete` or an `update` never touches the tree at all.
  SequenceDelta<T> _deltaOf(
    FugueMovableListState<T> state,
    Operation operation, {
    required List<FugueElementID> beforeIds,
    required List<T> beforeValues,
  }) {
    final afterIds = state.visibleIdentities();
    final afterValues = state.value;

    // Lazily: an insert never asks where anything used to be.
    late final placeBefore = <FugueElementID, int>{
      for (var i = 0; i < beforeIds.length; i++) beforeIds[i]: i,
    };

    if (operation is _MovableListInsertOperation<T>) {
      if (operation.items.isEmpty) {
        return SequenceDelta<T>.empty();
      }
      final first = operation.items.first.identityID;
      final at = afterIds.indexOf(first);
      return fugueInsertAtDelta<T>(
        at,
        operation.items.map((item) => item.value).toList(),
      );
    }

    if (operation is _MovableListMoveOperation<T>) {
      final from = placeBefore[operation.identityID];
      final to = afterIds.indexOf(operation.identityID);
      // A move that lost the last-writer-wins comparison, or that asked for
      // the place the element already had, moves nothing.
      if (from == null || to < 0 || from == to) {
        return SequenceDelta<T>.empty();
      }
      return SequenceDelta<T>([SeqMove<T>(from: from, to: to)]);
    }

    if (operation is _MovableListDeleteOperation<T>) {
      final places = <int>{};
      for (final item in operation.items) {
        final at = placeBefore[item.identityID];
        if (at != null) {
          places.add(at);
        }
      }
      return fugueDeleteDelta<T>(places.toList()..sort());
    }

    if (operation is _MovableListUpdateOperation<T>) {
      final entries = <(int, T)>[];
      for (final item in operation.items) {
        final at = placeBefore[item.identityID];
        // An update that lost the comparison leaves the value as it was.
        if (at != null && beforeValues[at] != afterValues[at]) {
          entries.add((at, afterValues[at]));
        }
      }
      return fugueReplaceDelta<T>(entries);
    }

    return SequenceDelta<T>.empty();
  }

  /// The version of the snapshot blob this build writes and reads.
  static const int _snapshotVersion = 1;

  /// Snapshot layout:
  /// - version: u8
  /// - elementsCount: uvarint
  /// - repeated `elementsCount` times:
  ///   - identityID: [FugueElementID] bytes
  ///   - position: [FugueElementID] bytes
  ///   - positionStamp: [OperationId.byteLength] bytes
  ///   - valueStamp: [OperationId.byteLength] bytes
  ///   - valueLen: uvarint
  ///   - value: [ValueCodec] bytes
  /// - floor: [ElementIdFloor]
  ///
  /// Only the visible elements go out, so every element comes back live.
  ///
  /// The Fugue tree is not encoded directly: it is rebuilt at restore time by
  /// inserting the snapshot identities at their winning positions in
  /// traversal order, which is sufficient to keep the projected list value
  /// stable across the snapshot boundary.
  @override
  Uint8List getSnapshotState() {
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;

    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    UVarint.write(visible.length, out);
    for (final positionID in visible) {
      final identityID = _identityForPosition(state, positionID)!;
      final element = state._elements[identityID]!;

      out
        ..add(identityID.toBytes())
        ..add(element.position.toBytes())
        ..add(element.positionStamp.toUint8List())
        ..add(element.valueStamp.toUint8List());

      UVarint.writeBytes(_valueCodec.encode(element.value), out);
    }
    ElementIdFloor.write(elementIdFloorForSnapshot(), out);
    return out.toBytes();
  }

  /// Decodes the snapshot and returns the seeded element map, preserving
  /// the original traversal order so [computeState] can rebuild the tree.
  ///
  /// Also seeds the element id floor from the snapshot trailer, so counters
  /// spent on identities and positions that were deleted and pruned are never
  /// reissued.
  Map<FugueElementID, _MovableElement<T>> _seedFromSnapshot() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return <FugueElementID, _MovableElement<T>>{};
    }

    var offset = SnapshotBlob.read(
      snapshot,
      version: _snapshotVersion,
      name: 'movable list',
    );
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;

    final result = <FugueElementID, _MovableElement<T>>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final identityRec = FugueElementID.readFromBytes(
        snapshot,
        offset: offset,
      );
      offset = identityRec.nextOffset;

      final positionRec = FugueElementID.readFromBytes(
        snapshot,
        offset: offset,
      );
      offset = positionRec.nextOffset;

      final positionStamp = OperationId.readFromBytes(
        snapshot,
        offset: offset,
      );
      offset += OperationId.byteLength;

      final valueStamp = OperationId.readFromBytes(
        snapshot,
        offset: offset,
      );
      offset += OperationId.byteLength;

      final valueRecord = UVarint.readBytes(
        snapshot,
        offset: offset,
        what: 'movable list snapshot value',
      );
      final value = _valueCodec.decode(valueRecord.value);
      offset = valueRecord.nextOffset;

      result[identityRec.value] = _MovableElement<T>(
        value: value,
        valueStamp: valueStamp,
        position: positionRec.value,
        positionStamp: positionStamp,
        // A snapshot holds the visible elements only.
        deleted: false,
      );
    }
    seedElementIdFloor(ElementIdFloor.read(snapshot, offset: offset));
    return result;
  }

  @override
  List<T> applyDelta(List<T> base, SequenceDelta<T> delta) => delta.apply(base);

  @override
  List<T> copyValue(List<T> value) => List<T>.of(value);

  @override
  String toString() {
    return 'CRDTFugueMovableList($id, $value)';
  }
}

/// State of a [CRDTFugueMovableListHandler].
///
/// Holds two pieces:
/// - a [FugueTree] of `FugueElementID` slots: each tree node represents a
///   position in the document, and the node's value is the **identity** that
///   "lives at" that position. The tree provides the interleaving-aware total
///   order from the Fugue algorithm.
/// - a `Map<identityID, MovableElement>` keyed by stable element identity,
///   carrying the LWW value and LWW current position of each element.
///
/// The visible list is the result of walking the tree in traversal order and
/// keeping only the slots whose identity still points back to them (i.e. the
/// LWW-winning position of the identity) and whose identity has not been
/// deleted.
class FugueMovableListState<T> {
  FugueMovableListState._({
    required FugueTree<FugueElementID> tree,
    required Map<FugueElementID, _MovableElement<T>> elements,
  })  : _tree = tree,
        _elements = elements;

  /// Creates an empty state.
  factory FugueMovableListState.empty() {
    return FugueMovableListState<T>._(
      tree: FugueTree<FugueElementID>.empty(),
      elements: <FugueElementID, _MovableElement<T>>{},
    );
  }

  final FugueTree<FugueElementID> _tree;
  final Map<FugueElementID, _MovableElement<T>> _elements;

  /// rebuilt (lazy) after every applyOperation
  List<T>? _cachedValues;

  /// rebuilt (lazy) after every applyOperation
  List<FugueElementID>? _cachedVisiblePositions;

  /// rebuilt (lazy) after every applyOperation
  List<FugueElementID>? _cachedIdentities;

  void _markDirty() {
    _cachedValues = null;
    _cachedVisiblePositions = null;
    _cachedIdentities = null;
  }

  void _resolveVisible() {
    if (_cachedValues != null &&
        _cachedVisiblePositions != null &&
        _cachedIdentities != null) {
      return;
    }

    final values = <T>[];
    final positions = <FugueElementID>[];
    final identities = <FugueElementID>[];
    for (final node in _tree.nodes()) {
      final identity = node.value;
      final element = _elements[identity];

      if (element == null || element.deleted) {
        continue;
      }

      if (element.position != node.id) {
        // This slot is orphaned (the identity has since moved elsewhere).
        // There is another node in the tree with the new position
        continue;
      }
      values.add(element.value);
      positions.add(node.id);
      identities.add(identity);
    }
    _cachedValues = values;
    _cachedVisiblePositions = positions;
    _cachedIdentities = identities;
  }

  /// Returns the public list value.
  List<T> get value {
    _resolveVisible();
    return _cachedValues!;
  }

  /// The identity of every visible element, in order.
  ///
  /// It comes out of the same walk that resolves [value], so a watched handler
  /// pays one traversal per operation rather than one for the values and
  /// another for the identities.
  ///
  /// The list is rebuilt from scratch whenever the state moves, so a caller
  /// that keeps a reference keeps the order as it was — which is what makes
  /// "before" and "after" comparable without copying either one.
  List<FugueElementID> visibleIdentities() {
    _resolveVisible();
    return _cachedIdentities!;
  }

  /// Returns the visible positions in traversal order.
  List<FugueElementID> get visiblePositions {
    _resolveVisible();
    return _cachedVisiblePositions!;
  }
}

/// Per-identity state in a [CRDTFugueMovableListHandler].
class _MovableElement<T> {
  _MovableElement({
    required this.value,
    required this.valueStamp,
    required this.position,
    required this.positionStamp,
    required this.deleted,
  });

  /// The value currently associated with this identity, picked by LWW on
  /// concurrent `update` operations.
  T value;

  /// The stamp of the write that put [value] here.
  ///
  /// A stamp rather than a clock: two peers can write in the same tick, and
  /// the peer is what settles which of the two wins on both of them.
  OperationId valueStamp;

  /// The position currently associated with this identity, picked by LWW on
  /// concurrent `move`/`insert` operations.
  FugueElementID position;

  /// The stamp of the write that put this identity at [position].
  OperationId positionStamp;

  /// Whether this identity has been deleted.
  bool deleted;
}
