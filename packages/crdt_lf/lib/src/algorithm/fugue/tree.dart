import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/node.dart';
import 'package:crdt_lf/src/algorithm/fugue/node_triple.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/algorithm/sqrt_decomposition/sqrt_decomposition.dart';

/// Implementation of the Fugue tree for collaborative text editing
///
/// ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text
/// Editing](https://arxiv.org/abs/2305.00583))
class FugueTree<T> {
  FugueTree._({
    required Map<FugueElementID, FugueNodeTriple<T>> nodes,
    required FugueElementID rootID,
  })  : _nodes = nodes,
        _rootID = rootID;

  /// Initializes a new empty Fugue tree
  factory FugueTree.empty() {
    // Initialize the tree with a root node
    final rootID = FugueElementID.nullID();
    final rootNode = FugueNode<T>(
      id: rootID,
      value: null,
      parentID: FugueElementID.nullID(),
      side: FugueSide.left,
    );
    final nodes = {
      rootID: FugueNodeTriple<T>(
        node: rootNode,
        leftChildren: [],
        rightChildren: [],
      ),
    };

    return FugueTree._(
      nodes: nodes,
      rootID: rootID,
    );
  }

  /// Creates a tree from a JSON object
  factory FugueTree.fromJson(
    Map<String, dynamic> json,
  ) {
    // Add nodes from the JSON object
    final nodesJson = json['nodes'] as Map<String, dynamic>;
    final nodes = <FugueElementID, FugueNodeTriple<T>>{};

    for (final entry in nodesJson.entries) {
      final id = FugueElementID.parse(entry.key);
      final triple =
          FugueNodeTriple<T>.fromJson(entry.value as Map<String, dynamic>);
      nodes[id] = triple;
    }

    final tree = FugueTree<T>._(
      nodes: nodes,
      rootID: FugueElementID.nullID(),
    ).._rebuildIndex();

    final stampsJson = json['stamps'] as Map<String, dynamic>?;
    if (stampsJson != null) {
      for (final entry in stampsJson.entries) {
        tree._stamps[FugueElementID.parse(entry.key)] =
            OperationId.parse(entry.value as String);
      }
    }

    return tree;
  }

  /// The nodes in the tree, indexed by ID
  final Map<FugueElementID, FugueNodeTriple<T>> _nodes;

  /// Root node ID
  final FugueElementID _rootID;

  /// The last-writer-wins stamp of the nodes whose value has been overwritten
  /// in place by [update].
  ///
  /// A node still carrying the value it was inserted with has no entry, and
  /// loses against any update. Only overwritten nodes are stored: the map
  /// stays empty for the insert/delete-only workloads, which is the case that
  /// matters — on text there is one node per element, and a stamp on every
  /// node would cost 24 bytes each.
  final Map<FugueElementID, OperationId> _stamps = {};

  /// Positional index over the in-order sequence of all structural nodes
  /// Answers position↔id and successor queries in `O(√n)`.
  ///
  /// - Never serialized;
  /// - Rebuilt on deserialization via [_rebuildIndex].
  final SqrtDecomposition<FugueElementID> _index =
      SqrtDecomposition<FugueElementID>();

  /// Returns all non-deleted values in the correct order
  ///
  /// Read out of [_index], which already holds the in-order sequence: no tree
  /// walk, and stretches of tombstones are skipped a whole block at a time.
  List<T> values() {
    final result = <T>[];
    _index.forEachLive((id) {
      final value = _nodes[id]!.node.value;
      if (value != null) {
        result.add(value);
      }
    });
    return result;
  }

  /// Returns all non-deleted nodes in the correct order
  List<FugueValueNode<T>> nodes() {
    final result = <FugueValueNode<T>>[];
    forEachLiveNode((id, value) {
      result.add(FugueValueNode<T>(id: id, value: value));
    });
    return result;
  }

  /// The number of non-deleted nodes, in `O(1)`.
  int get liveLength => _index.liveLength;

  /// Calls [action] on every non-deleted node, in sequence order.
  ///
  /// The streaming form of [nodes]: a caller that only reads each node once
  /// pays nothing for the list.
  void forEachLiveNode(void Function(FugueElementID id, T value) action) {
    _index.forEachLive((id) {
      final value = _nodes[id]!.node.value;
      if (value != null) {
        action(id, value);
      }
    });
  }

  /// The last-writer-wins stamps of the nodes an [update] overwrote.
  ///
  /// Bounded by the live nodes (because [delete] evicts).
  Map<FugueElementID, OperationId> get stamps =>
      Map<FugueElementID, OperationId>.unmodifiable(_stamps);

  /// Seeds an empty tree with [nodes], in sequence order, plus their [stamps].
  ///
  /// Node for node this is what `iterableInsert(0, nodes)` builds — a right
  /// spine hanging off the root — but it links the nodes directly and builds
  /// the positional index with a single [SqrtDecomposition.bulkBuild]. That
  /// turns the seed from n insertions of `O(√n)` into `O(n)`, which is the
  /// whole cost of opening a document from a snapshot.
  void bulkSeed(
    List<FugueValueNode<T>> nodes,
    Map<FugueElementID, OperationId> stamps,
  ) {
    assert(_nodes.length == 1, 'bulkSeed expects an empty tree');
    if (nodes.isEmpty) {
      return;
    }

    var parentID = _rootID;
    for (final node in nodes) {
      _nodes[node.id] = FugueNodeTriple<T>(
        node: FugueNode<T>(
          id: node.id,
          value: node.value,
          parentID: parentID,
          side: FugueSide.right,
        ),
        leftChildren: [],
        rightChildren: [],
      );
      _nodes[parentID]!.rightChildren.add(node.id);
      parentID = node.id;
    }

    _index.bulkBuild(
      nodes.map((node) => node.id).toList(),
      List<bool>.filled(nodes.length, true),
    );
    _stamps.addAll(stamps);
  }

  /// Inserts a list of nodes into the tree at the specified index.
  ///
  /// Convenience for the local-edit path: derives `leftOrigin`/`rightOrigin`
  /// from [index] and delegates to [iterableInsertChain].
  void iterableInsert(
    int index,
    Iterable<FugueValueNode<T>> nodes,
  ) {
    if (nodes.isEmpty) {
      return;
    }

    final leftOrigin =
        index == 0 ? FugueElementID.nullID() : findNodeAtPosition(index - 1);
    final rightOrigin = findNextNode(leftOrigin);

    iterableInsertChain(
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      nodes: nodes,
    );
  }

  /// Inserts a chain of nodes between [leftOrigin] and [rightOrigin].
  ///
  /// The first node is inserted with the given origins; each subsequent node
  /// is chained as a right child of the previously-inserted one, with the
  /// same [rightOrigin].
  ///
  /// The result is the same as inserting the nodes one by one at consecutive
  /// indexes, and the chain stays contiguous under concurrent insertions at
  /// the same position.
  void iterableInsertChain({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required Iterable<FugueValueNode<T>> nodes,
  }) {
    if (nodes.isEmpty) {
      return;
    }

    var previousID = leftOrigin;
    for (final node in nodes) {
      insert(
        newID: node.id,
        value: node.value,
        leftOrigin: previousID,
        rightOrigin: rightOrigin,
      );
      previousID = node.id;
    }
  }

  /// Inserts a new [FugueNode] into the tree with [newID] and [value]
  ///
  /// [leftOrigin] is the node at position `index-1`
  ///
  /// [rightOrigin] node after [leftOrigin] in traversal order
  ///
  /// If [leftOrigin] is an ancestor of [rightOrigin] the new node becomes a
  /// left child of [rightOrigin]; otherwise it becomes a right child of
  /// [leftOrigin]. When [leftOrigin] is unknown the node becomes a left child
  /// of [rightOrigin], and when neither origin is known it hangs off the root.
  void insert({
    required FugueElementID newID,
    required T value,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    // Determine if the new node should be a left or right child
    FugueNode<T> newNode;

    if (!leftOrigin.isNull &&
        _nodes.containsKey(leftOrigin) &&
        !rightOrigin.isNull &&
        _nodes.containsKey(rightOrigin)) {
      if (_isAncestorOf(leftOrigin, rightOrigin)) {
        // Insert as left child of rightOrigin to maintain order
        newNode = FugueNode<T>(
          id: newID,
          value: value,
          parentID: rightOrigin,
          side: FugueSide.left,
        );
      } else {
        // Insert as right child of leftOrigin
        newNode = FugueNode<T>(
          id: newID,
          value: value,
          parentID: leftOrigin,
          side: FugueSide.right,
        );
      }
    } else if (!leftOrigin.isNull && _nodes.containsKey(leftOrigin)) {
      // The new node will be a right child of leftOrigin
      newNode = FugueNode<T>(
        id: newID,
        value: value,
        parentID: leftOrigin,
        side: FugueSide.right,
      );
    } else if (!rightOrigin.isNull && _nodes.containsKey(rightOrigin)) {
      // The new node will be a left child of rightOrigin
      newNode = FugueNode<T>(
        id: newID,
        value: value,
        parentID: rightOrigin,
        side: FugueSide.left,
      );
    } else if (leftOrigin.isNull) {
      // If leftOrigin is null, the new node will be a right child of the root
      newNode = FugueNode<T>(
        id: newID,
        value: value,
        parentID: _rootID,
        side: FugueSide.right,
      );
    } else {
      // If neither leftOrigin nor rightOrigin exists, insert at the beginning
      newNode = FugueNode<T>(
        id: newID,
        value: value,
        parentID: _rootID,
        side: FugueSide.left,
      );
    }

    // Add the node to the tree
    _addNodeToTree(newNode);
  }

  /// Whether [descendant] sits in the subtree rooted at [ancestor].
  ///
  /// Both ids must be present in the tree.
  bool _isAncestorOf(FugueElementID ancestor, FugueElementID descendant) {
    // without right children nothing can be a right descendant.
    if (_nodes[ancestor]!.rightChildren.isEmpty) {
      return false;
    }

    // a direct child.
    if (_nodes[descendant]!.node.parentID == ancestor) {
      return true;
    }

    // `O(√n)`: with right children the in-order successor is the leftmost node
    // of the first right subtree, hence a descendant.
    if (_index.successorOf(ancestor) == descendant) {
      return true;
    }

    var current = descendant;
    while (current != _rootID) {
      final parentID = _nodes[current]?.node.parentID;
      if (parentID == null) {
        return false;
      }
      if (parentID == ancestor) {
        return true;
      }
      current = parentID;
    }
    return false;
  }

  /// Deletes a node from the tree (marks it as deleted, `⊥`)
  void delete(FugueElementID nodeID) {
    if (_nodes.containsKey(nodeID)) {
      _nodes[nodeID]!.node.value = null;
      // A tombstone refuses every update, so the stamp can never be needed
      // again: dropping it keeps [_stamps] bounded by the live nodes.
      _stamps.remove(nodeID);
      _index.setLive(nodeID, live: false);
    }
  }

  /// Overwrites the value of [nodeID] in place, keeping its identity, its
  /// position and its liveness.
  ///
  /// Last-writer-wins on [stamp]: [OperationId] orders by clock first and
  /// by peer second, and the peer is what settles two updates carrying an
  /// identical clock — a case the clock alone cannot order, and where letting
  /// the arrival order decide would leave two peers with different values.
  /// Re-applying the same update is therefore a no-op.
  ///
  /// Refuses unknown and tombstoned nodes. A deletion is monotone, so an
  /// update that loses the race against one — or that arrives after the
  /// tombstone has been dropped by a snapshot — must not bring the element
  /// back.
  ///
  /// Returns whether [value] won. The positional index is deliberately left
  /// untouched: neither liveness nor traversal order changes, so it stays
  /// valid and the call is `O(1)`.
  bool update({
    required FugueElementID nodeID,
    required T value,
    required OperationId stamp,
  }) {
    final triple = _nodes[nodeID];
    if (triple == null || triple.node.isDeleted) {
      return false;
    }

    final current = _stamps[nodeID];
    if (current != null && stamp.compareTo(current) <= 0) {
      return false;
    }

    triple.node.value = value;
    _stamps[nodeID] = stamp;
    return true;
  }

  /// Adds a node to the tree
  void _addNodeToTree(FugueNode<T> node) {
    final parentID = node.parentID;

    // Element ids are unique by construction, so an id already in the tree
    // means the history is broken.
    if (_nodes.containsKey(node.id)) {
      throw DuplicateNodeException('Node already exists: ${node.id}');
    }

    // Create a new triple for the node
    final nodeTriple = FugueNodeTriple<T>(
      node: node,
      leftChildren: [],
      rightChildren: [],
    );
    _nodes[node.id] = nodeTriple;

    // Same-side siblings are kept sorted by id.
    final siblings = node.side == FugueSide.left
        ? _nodes[parentID]!.leftChildren
        : _nodes[parentID]!.rightChildren;
    final position = _siblingInsertionPoint(siblings, node.id);
    siblings.insert(position, node.id);

    _indexInsert(node, position);
  }

  /// The index at which [id] belongs in the id-sorted [siblings] list.
  int _siblingInsertionPoint(List<FugueElementID> siblings, FugueElementID id) {
    var low = 0;
    var high = siblings.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (siblings[middle].compareTo(id) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Keeps [_index] in sync after [node] has been linked into the tree as the
  /// child at [position] on its side.
  void _indexInsert(FugueNode<T> node, int position) {
    final isLive = node.value != null;
    final predecessor = _indexPredecessorFor(node, position);
    if (predecessor == null) {
      _index.insertAtFront(node.id, live: isLive);
    } else {
      _index.insertAfter(predecessor, node.id, live: isLive);
    }
  }

  /// The in-order predecessor of [node], linked as the child at [position] on
  /// its side, or `null` when [node] sorts at the very front of the sequence.
  FugueElementID? _indexPredecessorFor(FugueNode<T> node, int position) {
    final parentID = node.parentID;
    final parentTriple = _nodes[parentID]!;
    final siblings = node.side == FugueSide.left
        ? parentTriple.leftChildren
        : parentTriple.rightChildren;

    // A previous sibling exists: predecessor is the in-order-last node of its
    // subtree.
    if (position > 0) {
      return _inOrderLastOfSubtree(siblings[position - 1]);
    }

    // [node] is the first child on its side.
    if (node.side == FugueSide.right) {
      if (parentID == _rootID) {
        // The root emits no value, so the predecessor is the in-order-last node
        // of the root's left subtree, or the front if there is none.
        final left = parentTriple.leftChildren;
        return left.isEmpty ? null : _inOrderLastOfSubtree(left.last);
      }
      // A node immediately precedes its first right child in traversal order.
      return parentID;
    }

    // [node] now opens its parent's region: it sorts before every left sibling
    // already there, and before the parent itself when there are none. Taking
    // the predecessor of the parent would be wrong as soon as the parent has
    // other left children, because those come between the two.
    final regionStart =
        siblings.length > 1 ? _inOrderFirstOfSubtree(siblings[1]) : parentID;
    if (regionStart == _rootID) {
      // The root emits no value and nothing precedes its left subtree.
      return null;
    }
    return _index.predecessorOf(regionStart);
  }

  /// The last node visited by an in-order traversal of [id]'s subtree, i.e.
  /// following the right-children spine to its deepest end.
  FugueElementID _inOrderLastOfSubtree(FugueElementID id) {
    var current = id;
    while (_nodes[current]!.rightChildren.isNotEmpty) {
      current = _nodes[current]!.rightChildren.last;
    }
    return current;
  }

  /// The first node visited by an in-order traversal of [id]'s subtree, i.e.
  /// following the left-children spine to its deepest end.
  FugueElementID _inOrderFirstOfSubtree(FugueElementID id) {
    var current = id;
    while (_nodes[current]!.leftChildren.isNotEmpty) {
      current = _nodes[current]!.leftChildren.first;
    }
    return current;
  }

  /// Rebuilds [_index] from the tree in `O(n)`, used after deserialization.
  void _rebuildIndex() {
    final ids = <FugueElementID>[];
    final live = <bool>[];
    _collectStructuralInOrder(_rootID, ids, live);
    _index.bulkBuild(ids, live);
  }

  /// In-order traversal collecting **all** structural nodes except the root
  /// (tombstones included), as parallel id/liveness lists for [_index].
  void _collectStructuralInOrder(
    FugueElementID nodeID,
    List<FugueElementID> ids,
    List<bool> live,
  ) {
    final stack = <_TraversalStep>[_TraversalStep(nodeID, emitSelf: false)];

    while (stack.isNotEmpty) {
      final step = stack.removeLast();
      final triple = _nodes[step.id];
      if (triple == null) {
        continue;
      }

      if (step.emitSelf) {
        if (step.id != _rootID) {
          ids.add(step.id);
          live.add(triple.node.value != null);
        }
        continue;
      }

      for (final childID in triple.rightChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
      stack.add(_TraversalStep(step.id, emitSelf: true));
      for (final childID in triple.leftChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
    }
  }

  /// Finds the node at the specified [position], or a null id if [position] is
  /// negative or past the last live node.
  ///
  /// Backed by [_index]: `O(√n)` instead of a full in-order traversal.
  FugueElementID findNodeAtPosition(int position) {
    return _index.liveAt(position) ?? FugueElementID.nullID();
  }

  /// The live index of a caret anchored immediately **after** [nodeID]: the
  /// number of live nodes up to and including it — or strictly before it, if
  /// [nodeID] is a tombstone (the caret stays where the element used to be).
  ///
  /// Returns `null` for an id unknown to this tree. Backed by [_index]:
  /// `O(√n)`.
  int? liveIndexAfter(FugueElementID nodeID) {
    final triple = _nodes[nodeID];
    if (triple == null) {
      return null;
    }
    final rank = _index.liveRankOf(nodeID);
    if (rank == -1) {
      return null;
    }
    return triple.node.isDeleted ? rank : rank + 1;
  }

  /// Finds the next node after [nodeID] in the traversal, tombstones included,
  /// or a null id when [nodeID] is the last node of the sequence.
  ///
  /// A null [nodeID] means "before everything", so it resolves to the first
  /// node of the sequence. Callers use it to anchor an insertion at index `0`.
  FugueElementID findNextNode(FugueElementID nodeID) {
    if (!_nodes.containsKey(nodeID)) {
      return FugueElementID.nullID();
    }

    // The root sits before every other node and is the only structural node
    // kept out of [_index], so its successor is the head of the sequence.
    if (nodeID == _rootID) {
      return _index.first() ?? FugueElementID.nullID();
    }

    // guard for appending at the end, the sequential-typing path.
    if (_index.last() == nodeID) {
      return FugueElementID.nullID();
    }

    // guard for editing inside a document: a right child with no left
    // children of its own opens its subtree, so it is the successor.
    final rightChildren = _nodes[nodeID]!.rightChildren;
    if (rightChildren.isNotEmpty &&
        _nodes[rightChildren.first]!.leftChildren.isEmpty) {
      return rightChildren.first;
    }

    return _index.successorOf(nodeID) ?? FugueElementID.nullID();
  }

  /// Serializes the tree to JSON format
  ///
  /// Carries the [update] stamps next to the nodes. They are part of the
  /// state — without them a restored tree would accept an update it had
  /// already rejected — so a round-trip that dropped them would be a trap.
  Map<String, dynamic> toJson() {
    final nodesJson = <String, dynamic>{};
    for (final entry in _nodes.entries) {
      nodesJson[entry.key.toString()] = entry.value.toJson();
    }

    final stampsJson = <String, dynamic>{};
    for (final entry in _stamps.entries) {
      stampsJson[entry.key.toString()] = entry.value.toString();
    }

    return {
      'nodes': nodesJson,
      'stamps': stampsJson,
    };
  }

  /// Returns a string representation of the tree for debugging
  @override
  String toString() {
    final buffer = StringBuffer()..writeln('Tree:');
    _buildTreeString(_rootID, 0, buffer);
    return buffer.toString();
  }

  /// Helper to build the string representation of a node and its children
  void _buildTreeString(FugueElementID nodeID, int depth, StringBuffer buffer) {
    if (!_nodes.containsKey(nodeID)) return;

    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;

    final indent = '  ' * depth;
    buffer
      ..writeln('$indent$node')
      ..writeln('$indent Left children:');
    for (final childID in leftChildren) {
      _buildTreeString(childID, depth + 1, buffer);
    }

    buffer.writeln('$indent Right children:');
    for (final childID in rightChildren) {
      _buildTreeString(childID, depth + 1, buffer);
    }
  }
}

/// One frame of the explicit-stack in-order traversals in [FugueTree].
///
/// `emitSelf == false` expands the node (pushing its children and its own
/// emit frame); `emitSelf == true` visits the node itself.
class _TraversalStep {
  _TraversalStep(this.id, {required this.emitSelf});

  final FugueElementID id;
  final bool emitSelf;
}
