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
  /// (live nodes and tombstones), answering position↔id queries in `O(√n)`
  /// instead of an `O(n)` traversal.
  ///
  /// Derived accelerator kept in sync by [_addNodeToTree] and [delete]; never
  /// serialized, rebuilt from the tree on deserialization via [_rebuildIndex].
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

  /// Traverses the tree starting from the specified node
  ///
  /// Visits recursively the left children,
  /// then the node itself, then the right children
  /// Collects the non-deleted values (different from `⊥`)
  List<K> _traverse<K>(
    FugueElementID nodeID,
    K Function(FugueValueNode<T> node) transform,
  ) {
    final result = <K>[];

    if (!_nodes.containsKey(nodeID)) {
      return result;
    }

    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;

    // Recursively visit left children
    for (final childID in leftChildren) {
      result.addAll(_traverse<K>(childID, transform));
    }

    // Visit the node itself if not deleted
    final value = node.value;
    if (value != null) {
      result.add(
        transform(
          FugueValueNode(
            id: node.id,
            value: value,
          ),
        ),
      );
    }

    // Recursively visit right children
    for (final childID in rightChildren) {
      result.addAll(_traverse<K>(childID, transform));
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
  /// same [rightOrigin]. This is the "non-interleaving" Fugue insertion used
  /// when applying a batch insert received from a peer: the origins come
  /// from the operation itself, not from a local index, so this is the
  /// method that handler `applyOperation` paths should call.
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
  /// if [leftOrigin] exists and [rightOrigin] is a right child of [leftOrigin],
  /// the new node will be a left child of [rightOrigin]
  /// otherwise if [leftOrigin] exists, the new node will be a right child
  /// of [leftOrigin]
  /// otherwise, the new node will be a left child of [rightOrigin]
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
      // Check if rightOrigin is a right child of leftOrigin
      final leftOriginTriple = _nodes[leftOrigin]!;
      if (leftOriginTriple.rightChildren.contains(rightOrigin)) {
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

  /// Deletes a node from the tree (marks it as deleted, `⊥`)
  void delete(FugueElementID nodeID) {
    if (_nodes.containsKey(nodeID)) {
      _nodes[nodeID]!.node.value = null;
      _index.setLive(nodeID, live: false);
    }
  }

  /// Updates a [FugueNode] by deleting the old value and inserting a new one.
  void update({
    required FugueElementID nodeID,
    required FugueElementID newID,
    required T newValue,
  }) {
    // Check if the node exists and is not already deleted
    if (!_nodes.containsKey(nodeID) || _nodes[nodeID]!.node.isDeleted) {
      return;
    }

    final index = _index.liveRankOf(nodeID);
    if (index == -1) return;

    delete(nodeID);

    iterableInsert(index, [
      FugueValueNode(id: newID, value: newValue),
    ]);
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

    // Update the parent's children list
    if (node.side == FugueSide.left) {
      _nodes[parentID]!.leftChildren.add(node.id);
    } else {
      _nodes[parentID]!.rightChildren.add(node.id);
    }

    _indexInsert(node);
  }

  /// Keeps [_index] in sync after [node] has been linked into the tree.
  void _indexInsert(FugueNode<T> node) {
    final isLive = node.value != null;

    // Re-linking a previously-seen id (e.g. a resurrected tombstone): keep its
    // position, just refresh liveness.
    if (_index.contains(node.id)) {
      _index.setLive(node.id, live: isLive);
      return;
    }

    final predecessor = _indexPredecessorFor(node);
    if (predecessor == null) {
      _index.insertAtFront(node.id, live: isLive);
    } else {
      _index.insertAfter(predecessor, node.id, live: isLive);
    }
  }

  /// The in-order predecessor of [node] (just appended as the last child on its
  /// side), or `null` when [node] sorts at the very front of the sequence.
  FugueElementID? _indexPredecessorFor(FugueNode<T> node) {
    final parentID = node.parentID;
    final parentTriple = _nodes[parentID]!;
    final siblings = node.side == FugueSide.left
        ? parentTriple.leftChildren
        : parentTriple.rightChildren;

    // A previous sibling exists: predecessor is the in-order-last node of its
    // subtree.
    if (siblings.length >= 2) {
      return _inOrderLastOfSubtree(siblings[siblings.length - 2]);
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
    final triple = _nodes[nodeID];
    if (triple == null) {
      return;
    }
    for (final childID in triple.leftChildren) {
      _collectStructuralInOrder(childID, ids, live);
    }
    if (nodeID != _rootID) {
      ids.add(nodeID);
      live.add(triple.node.value != null);
    }
    for (final childID in triple.rightChildren) {
      _collectStructuralInOrder(childID, ids, live);
    }
  }

  /// Finds the node at the specified [position], or a null id if [position] is
  /// negative or past the last live node.
  ///
  /// Backed by [_index]: `O(√n)` instead of a full in-order traversal.
  FugueElementID findNodeAtPosition(int position) {
    return _index.liveAt(position) ?? FugueElementID.nullID();
  }

  /// Finds the next node after [nodeID] in the traversal
  FugueElementID findNextNode(FugueElementID nodeID) {
    if (!_nodes.containsKey(nodeID)) {
      return FugueElementID.nullID();
    }

    final nodeTriple = _nodes[nodeID]!;

    // 1. If it has right children, the next is the first right child
    if (nodeTriple.rightChildren.isNotEmpty) {
      return nodeTriple.rightChildren.first;
    }

    // Fast path: the in-order-last structural node has no successor. The climb
    // below would reach this same conclusion in `O(depth)`; the index answers
    // it in `O(√n)`, which keeps appending at the end (typing) sublinear.
    if (_index.last() == nodeID) {
      return FugueElementID.nullID();
    }

    // 2. Otherwise, climb up the tree until finding a node that is a left child
    // and return its right sibling
    var current = nodeID;
    while (!current.isNull) {
      final currentNode = _nodes[current]!.node;
      if (currentNode.side == FugueSide.left) {
        // Find the right sibling
        final parent = currentNode.parentID;
        if (!_nodes.containsKey(parent)) {
          break;
        }

        final parentTriple = _nodes[parent]!;
        final rightSiblings = parentTriple.rightChildren;
        if (rightSiblings.isNotEmpty) {
          return rightSiblings.first;
        }
      }
      current = currentNode.parentID;
    }

    // 3. If no right sibling is found, return null
    return FugueElementID.nullID();
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
