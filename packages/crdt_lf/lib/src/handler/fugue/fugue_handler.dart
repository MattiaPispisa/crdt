import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// Lazily-resolved state shared by Fugue-based handlers.
///
/// Wraps a [FugueTree] (the source of truth) and memoizes the two derived
/// projections — the ordered [FugueValueNode]s and the public value — so
/// that a batch of mutations resolves them at most once, on the next read.
///
/// `T` is the element type stored in the tree, `V` is the public value type
/// (`String` for text, `List<T>` for a list). The projection from the tree to
/// the public value is provided at construction time.
class FugueState<T, V> {
  /// Creates a state over `tree`, projecting the public value with `project`.
  FugueState(this._tree, this._project);

  final FugueTree<T> _tree;
  final V Function(FugueTree<T> tree) _project;

  List<FugueValueNode<T>>? _cachedNodes;
  V? _cachedValue;

  /// The ordered value nodes, resolved lazily from the tree.
  List<FugueValueNode<T>> get _nodes => _cachedNodes ??= _tree.nodes();

  /// The public value, resolved lazily from the tree.
  V get _value => _cachedValue ??= _project(_tree);

  /// Discards the resolved projections after a tree mutation; they are
  /// resolved again lazily on the next read.
  void _markDirty() {
    _cachedNodes = null;
    _cachedValue = null;
  }
}

/// Shared base for handlers backed by a Fugue tree.
///
/// It owns everything the text and list variants have in common:
/// - the per-peer element-id counter ([nextCounter]),
/// - the cache lifecycle (lazy resolution and in-place incremental tree
///   mutation),
/// - history replay and snapshot framing,
/// - the [delete] operation and the tree-navigation helpers used to build
///   inserts and updates.
///
/// Subclasses provide the element type `T`, the public value type `V` and the
/// concrete state type `S`, plus the extension points that depend on the
/// concrete operation encoding (see the methods grouped under
/// "Extension points").
///
/// ## Note on `T`
/// The Fugue tree uses a `null` value to mark a deleted element, so `T` must
/// be non-nullable: a stored `null` would be indistinguishable from a
/// deletion.
abstract class FugueHandler<T, V, S extends FugueState<T, V>>
    extends Handler<S> {
  /// Creates a Fugue handler bound to [doc] with the given handler [id].
  FugueHandler(super.doc, String id) : _id = id;

  final String _id;

  /// Per-peer element-id counter, lazily seeded on first use.
  int? _counter;

  @override
  String get id => _id;

  // --- Extension points implemented by subclasses ---

  /// Creates an empty state (an empty tree with this handler's projection).
  S createEmptyState();

  /// Applies a single decoded [operation] to [tree].
  void applyToTree(FugueTree<T> tree, Operation operation);

  /// The element ids produced by this peer in [operation] — insert ids and
  /// update new-node ids — used to seed [nextCounter].
  ///
  /// Returns nothing for operations that do not create nodes (e.g. delete).
  Iterable<FugueElementID> producedElementIds(Operation operation);

  /// Builds the delete operation for the given [nodeIDs].
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs);

  /// Encodes a single element value for the snapshot blob.
  Uint8List encodeValue(T value);

  /// Decodes a single element value from the snapshot blob.
  T decodeValue(Uint8List bytes);

  // --- Shared public API ---

  /// The current value, computed from changes and snapshot.
  V get value => _cachedOrComputedState()._value;

  /// Deletes [count] elements starting at [index].
  void delete(int index, int count) {
    final state = _cachedOrComputedState();

    // Collect targets first to avoid index drift while deleting.
    final targets = <FugueElementID>[];
    for (var i = 0; i < count; i++) {
      final nodeID = state._tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    if (targets.isEmpty) {
      return;
    }

    doc.registerOperation(buildDeleteOperation(targets));
  }

  // --- Helpers for subclass insert/update ---

  /// The left origin for an insertion at [index]: the root id for index `0`,
  /// otherwise the node currently at `index - 1`.
  FugueElementID originBefore(int index) {
    if (index == 0) {
      return FugueElementID.nullID();
    }
    return _cachedOrComputedState()._tree.findNodeAtPosition(index - 1);
  }

  /// The node that follows [id] in traversal order.
  FugueElementID nodeAfter(FugueElementID id) {
    return _cachedOrComputedState()._tree.findNextNode(id);
  }

  /// The node currently at [index], or a null id if out of range.
  FugueElementID nodeAt(int index) {
    return _cachedOrComputedState()._tree.findNodeAtPosition(index);
  }

  /// Returns the next unique element counter for this peer.
  ///
  /// Seeded lazily on first use by scanning the snapshot nodes and every
  /// operation for the highest counter produced by this peer.
  int nextCounter() {
    if (_counter == null) {
      var max = -1;
      void consider(FugueElementID id) {
        if (!id.isNull && id.replicaID == doc.peerId) {
          final c = id.counter!;
          if (c > max) max = c;
        }
      }

      for (final node in _initialState()) {
        consider(node.id);
      }
      for (final op in operations()) {
        producedElementIds(op).forEach(consider);
      }
      _counter = max + 1;
    }
    final result = _counter!;
    _counter = result + 1;
    return result;
  }

  // --- Cache lifecycle ---

  S _cachedOrComputedState() {
    final cached = cachedState;
    if (cached != null) {
      return cached;
    }

    final state = _computeState();
    updateCachedState(state);
    return state;
  }

  @override
  S? incrementCachedState({
    required Operation operation,
    required S state,
  }) {
    // The tree is mutated in place; the projections are resolved lazily on
    // the next read instead of after every operation.
    try {
      applyToTree(state._tree, operation);
      return state.._markDirty();
    } catch (_) {
      // The tree may be half-mutated: invalidate the cache.
      return null;
    }
  }

  S _computeState() {
    final state = createEmptyState();

    // Seed from the snapshot, then replay the history.
    state._tree.iterableInsert(0, _initialState());
    for (final operation in operations()) {
      applyToTree(state._tree, operation);
    }

    // The projections are resolved lazily on the first read.
    return state;
  }

  // --- Snapshot framing ---

  @override
  Uint8List getSnapshotState() {
    final nodes = _cachedOrComputedState()._nodes;

    final out = BytesBuilder(copy: false);
    UVarint.write(nodes.length, out);
    for (final node in nodes) {
      final idBytes = node.id.toBytes();
      UVarint.write(idBytes.length, out);
      out.add(idBytes);

      final valueBytes = encodeValue(node.value);
      UVarint.write(valueBytes.length, out);
      out.add(valueBytes);
    }
    return out.toBytes();
  }

  /// Decodes the snapshot nodes for this handler, or an empty list if there
  /// is no snapshot.
  List<FugueValueNode<T>> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return [];
    }

    var offset = 0;
    final countRec = UVarint.read(snapshot, offset: offset);
    offset = countRec.nextOffset;
    final nodes = <FugueValueNode<T>>[];
    for (var i = 0; i < countRec.value; i += 1) {
      final idLenRec = UVarint.read(snapshot, offset: offset);
      offset = idLenRec.nextOffset;
      final idEnd = offset + idLenRec.value;
      final id = FugueElementID.fromBytes(
        Uint8List.sublistView(snapshot, offset, idEnd),
      );
      offset = idEnd;

      final valLenRec = UVarint.read(snapshot, offset: offset);
      offset = valLenRec.nextOffset;
      final valEnd = offset + valLenRec.value;
      final value = decodeValue(
        Uint8List.sublistView(snapshot, offset, valEnd),
      );
      offset = valEnd;

      nodes.add(FugueValueNode<T>(id: id, value: value));
    }
    return nodes;
  }
}
