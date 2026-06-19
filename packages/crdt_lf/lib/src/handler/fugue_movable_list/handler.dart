import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_cache.dart';
import 'package:hlc_dart/hlc_dart.dart';

part 'operation.dart';

/// # CRDT List with Fugue implementation and movable elements
///
/// A list CRDT that supports `insert`, `delete`, `update` **and** an explicit
/// `move` operation that preserves the identity of the moved element across
/// concurrent reorderings (see Kleppmann, [Moving Elements in List CRDTs](https://martin.kleppmann.com/2020/04/27/papoc-list-move.html)).
///
/// Conflict resolution combines:
/// - the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving;
/// - a **last-writer-wins register** (keyed on the change HLC) for the
///   "current position" of each element. Concurrent moves of the same element
///   converge to a single winning destination instead of duplicating the
///   element.
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
class CRDTFugueMovableListHandler<T> extends Handler<FugueMovableListState<T>>
    with FugueCache<FugueMovableListState<T>> {
  /// Creates a movable list handler bound to [doc] with the given [id].
  ///
  /// [valueCodec] is an optional codec for encoding/decoding `T` values to
  /// bytes; default is [JsonValueCodec].
  CRDTFugueMovableListHandler(
    super.doc,
    String id, {
    ValueCodec<T>? valueCodec,
  })  : _id = id,
        _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final String _id;
  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationFactory operationFactory =
      _FugueMovableListOperationFactory<T>(this).fromBytes;

  /// Returns the current list value.
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
        hlc: doc.hlc,
      ),
    );
  }

  /// Updates the value of the element currently at visible position [index].
  void update(int index, T value) {
    final identity = _identityAtVisibleIndex(index);
    if (identity == null) {
      return;
    }

    doc.registerOperation(
      _MovableListUpdateOperation<T>.fromHandler(
        this,
        hlc: doc.hlc,
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
    Operation operation,
  ) {
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
            valueHlc: HybridLogicalClock.initialize(),
            position: item.positionID,
            positionHlc: HybridLogicalClock.initialize(),
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
        if (operation.hlc.happenedAfter(element.positionHlc)) {
          element
            ..position = operation.newPositionID
            ..positionHlc = operation.hlc;
        }
      }
    } else if (operation is _MovableListUpdateOperation<T>) {
      for (final item in operation.items) {
        final element = state._elements[item.identityID];
        if (element != null) {
          // last written wins
          if (operation.hlc.happenedAfter(element.valueHlc)) {
            element
              ..value = item.value
              ..valueHlc = operation.hlc;
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
  }

  /// Snapshot layout:
  /// - elementsCount: uvarint
  /// - repeated `elementsCount` times:
  ///   - identityID: [FugueElementID] bytes
  ///   - position: [FugueElementID] bytes
  ///   - positionHlc: 8 bytes
  ///   - valueHlc: 8 bytes
  ///   - deleted: u8 (0/1)
  ///   - valueLen: uvarint
  ///   - value: [ValueCodec] bytes
  ///
  /// The Fugue tree is not encoded directly: it is rebuilt at restore time by
  /// inserting the snapshot identities at their winning positions in
  /// traversal order, which is sufficient to keep the projected list value
  /// stable across the snapshot boundary.
  @override
  Uint8List getSnapshotState() {
    final state = cachedOrComputedState();
    final visible = state.visiblePositions;

    final out = BytesBuilder(copy: false);
    UVarint.write(visible.length, out);
    for (final positionID in visible) {
      final identityID = _identityForPosition(state, positionID)!;
      final element = state._elements[identityID]!;

      out
        ..add(identityID.toBytes())
        ..add(element.position.toBytes())
        ..add(element.positionHlc.toUint8List())
        ..add(element.valueHlc.toUint8List())
        ..addByte(element.deleted ? 1 : 0);

      final valBytes = _valueCodec.encode(element.value);
      UVarint.write(valBytes.length, out);
      out.add(valBytes);
    }
    return out.toBytes();
  }

  /// Decodes the snapshot and returns the seeded element map, preserving
  /// the original traversal order so [computeState] can rebuild the tree.
  Map<FugueElementID, _MovableElement<T>> _seedFromSnapshot() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return <FugueElementID, _MovableElement<T>>{};
    }

    var offset = 0;
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

      final positionHlc = HybridLogicalClock.fromUint8List(
        snapshot,
        offset: offset,
      );
      offset += 8;

      final valueHlc = HybridLogicalClock.fromUint8List(
        snapshot,
        offset: offset,
      );
      offset += 8;

      if (offset >= snapshot.length) {
        throw const FormatException(
          'Truncated movable list snapshot deleted flag',
        );
      }
      final deleted = snapshot[offset] != 0;
      offset += 1;

      final valLenRec = UVarint.read(snapshot, offset: offset);
      offset = valLenRec.nextOffset;
      final valEnd = offset + valLenRec.value;
      if (valEnd > snapshot.length) {
        throw const FormatException(
          'Truncated movable list snapshot value',
        );
      }
      final value = _valueCodec.decode(
        Uint8List.sublistView(snapshot, offset, valEnd),
      );
      offset = valEnd;

      result[identityRec.value] = _MovableElement<T>(
        value: value,
        valueHlc: valueHlc,
        position: positionRec.value,
        positionHlc: positionHlc,
        deleted: deleted,
      );
    }
    return result;
  }

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

  void _markDirty() {
    _cachedValues = null;
    _cachedVisiblePositions = null;
  }

  void _resolveVisible() {
    if (_cachedValues != null && _cachedVisiblePositions != null) {
      return;
    }

    final values = <T>[];
    final positions = <FugueElementID>[];
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
    }
    _cachedValues = values;
    _cachedVisiblePositions = positions;
  }

  /// Returns the public list value.
  List<T> get value {
    _resolveVisible();
    return _cachedValues!;
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
    required this.valueHlc,
    required this.position,
    required this.positionHlc,
    required this.deleted,
  });

  /// The value currently associated with this identity, picked by LWW on
  /// concurrent `update` operations.
  T value;

  /// The clock attached to the [value] (last write wins).
  HybridLogicalClock valueHlc;

  /// The position currently associated with this identity, picked by LWW on
  /// concurrent `move`/`insert` operations.
  FugueElementID position;

  /// The clock attached to the [position] (last write wins).
  HybridLogicalClock positionHlc;

  /// Whether this identity has been deleted.
  bool deleted;
}
