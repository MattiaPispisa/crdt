import 'package:crdt_lf/crdt_lf.dart';
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

    return FugueTree._(
      nodes: nodes,
      rootID: FugueElementID.nullID(),
    ).._rebuildIndex();
  }

  /// The nodes in the tree, indexed by ID
  final Map<FugueElementID, FugueNodeTriple<T>> _nodes;

  /// Root node ID
  final FugueElementID _rootID;

  /// Positional index over the in-order sequence of all structural nodes
  /// Answers position↔id and successor queries in `O(√n)`.
  ///
  /// - Never serialized;
  /// - Rebuilt on deserialization via [_rebuildIndex].
  final SqrtDecomposition<FugueElementID> _index =
      SqrtDecomposition<FugueElementID>();

  /// Returns all non-deleted values in the correct order
  List<T> values() {
    return _traverse(_rootID, (node) => node.value);
  }

  /// Returns all non-deleted nodes in the correct order
  List<FugueValueNode<T>> nodes() {
    return _traverse(_rootID, (node) => node);
  }

  /// Traverses the tree starting from the specified node.
  ///
  /// Visits the left children, then the node itself, then the right children,
  /// collecting the non-deleted values (different from `⊥`).
  List<K> _traverse<K>(
    FugueElementID nodeID,
    K Function(FugueValueNode<T> node) transform,
  ) {
    final result = <K>[];
    final stack = <_TraversalStep>[_TraversalStep(nodeID, emitSelf: false)];

    while (stack.isNotEmpty) {
      final step = stack.removeLast();
      final nodeTriple = _nodes[step.id];
      if (nodeTriple == null) {
        continue;
      }
      final node = nodeTriple.node;

      if (step.emitSelf) {
        // Visit the node itself if not deleted.
        final value = node.value;
        if (value != null) {
          result.add(transform(FugueValueNode(id: node.id, value: value)));
        }
        continue;
      }

      // Push in reverse so the pop order is: left children, self, then right
      // children (each child list kept in its own order).
      for (final childID in nodeTriple.rightChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
      stack.add(_TraversalStep(step.id, emitSelf: true));
      for (final childID in nodeTriple.leftChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
    }

    return result;
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
      _index.setLive(nodeID, live: false);
    }
  }

  /// Updates a [FugueNode]: tombstones [nodeID] and puts [newID], carrying
  /// [newValue], in the slot [nodeID] occupied.
  ///
  /// Does nothing when [nodeID] is unknown to this tree.
  void update({
    required FugueElementID nodeID,
    required FugueElementID newID,
    required T newValue,
  }) {
    final triple = _nodes[nodeID];
    if (triple == null) {
      return;
    }

    if (!triple.node.isDeleted) {
      delete(nodeID);
    }

    _addNodeToTree(
      FugueNode<T>(
        id: newID,
        value: newValue,
        parentID: nodeID,
        side: FugueSide.left,
      ),
    );
  }

  /// Adds a node to the tree
  void _addNodeToTree(FugueNode<T> node) {
    final parentID = node.parentID;

    if (_nodes.containsKey(node.id)) {
      if (_nodes[node.id]!.node.value != null) {
        throw DuplicateNodeException('Node already exists: ${node.id}');
      }
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

    // Re-linking a previously-seen id (e.g. a resurrected tombstone): keep its
    // position, just refresh liveness.
    if (_index.contains(node.id)) {
      _index.setLive(node.id, live: isLive);
      return;
    }

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

    // First left child: it sorts immediately before its parent.
    if (parentID == _rootID) {
      return null;
    }
    return _index.predecessorOf(parentID);
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
  FugueElementID findNextNode(FugueElementID nodeID) {
    if (!_nodes.containsKey(nodeID)) {
      return FugueElementID.nullID();
    }

    // The root is the only structural node kept out of [_index].
    if (nodeID == _rootID) {
      final rightChildren = _nodes[_rootID]!.rightChildren;
      if (rightChildren.isEmpty) {
        return FugueElementID.nullID();
      }
      return _nodes[_rootID]!.leftChildren.isEmpty
          ? _index.first() ?? FugueElementID.nullID()
          : _inOrderFirstOfSubtree(rightChildren.first);
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
  Map<String, dynamic> toJson() {
    final nodesJson = <String, dynamic>{};
    for (final entry in _nodes.entries) {
      nodesJson[entry.key.toString()] = entry.value.toJson();
    }

    return {
      'nodes': nodesJson,
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
