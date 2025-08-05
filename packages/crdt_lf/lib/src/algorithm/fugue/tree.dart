import 'package:crdt_lf/crdt_lf.dart';

/// Implementation of the Fugue tree for collaborative text editing
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
    );
  }

  /// The nodes in the tree, indexed by ID
  final Map<FugueElementID, FugueNodeTriple<T>> _nodes;

  /// Root node ID
  final FugueElementID _rootID;

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

  /// Inserts a list of nodes into the tree at the specified index
  void iterableInsert(
    int index,
    Iterable<FugueValueNode<T>> nodes,
  ) {
    if (nodes.isEmpty) {
      return;
    }

    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin =
        index == 0 ? FugueElementID.nullID() : findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = findNextNode(leftOrigin);

    // Insert first node
    final firstNodeID = nodes.first.id;
    insert(
      newID: firstNodeID,
      value: nodes.first.value,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
    );

    // Insert remaining nodes as right children of the previous node
    var previousID = firstNodeID;
    for (final value in nodes.skip(1)) {
      final newNodeID = value.id;
      insert(
        newID: newNodeID,
        value: value.value,
        leftOrigin: previousID,
        rightOrigin: rightOrigin,
      );
      previousID = newNodeID;
    }
  }

  /// Inserts a new [FugueNode] into the tree with [newID] and [value]
  ///
  /// [leftOrigin] is the node at position `index-1`
  ///
  /// [rightOrigin] node after [leftOrigin] in traversal order
  ///
  /// if [leftOrigin] exists, the new node will be a right child of leftOrigin
  /// otherwise, the new node will be a left child of [rightOrigin]
  void insert({
    required FugueElementID newID,
    required T value,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    // Determine if the new node should be a left or right child
    FugueNode<T> newNode;

    if (!leftOrigin.isNull && _nodes.containsKey(leftOrigin)) {
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

    final index = nodes().indexWhere((node) => node.id == nodeID);
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
  }

  /// Finds the node at the specified position in the tree
  FugueElementID findNodeAtPosition(int position) {
    return _findNodeAtPositionRecursive(
      nodeID: _rootID,
      targetPos: position,
      currentPos: _CurrentPosition(-1),
    );
  }

  /// Recursive helper to find the node at the specified position
  FugueElementID _findNodeAtPositionRecursive({
    required FugueElementID nodeID,
    required int targetPos,
    required _CurrentPosition currentPos,
  }) {
    if (!_nodes.containsKey(nodeID)) {
      return FugueElementID.nullID();
    }

    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;

    // Check left children
    for (final childID in leftChildren) {
      final result = _findNodeAtPositionRecursive(
        nodeID: childID,
        targetPos: targetPos,
        currentPos: currentPos,
      );
      if (!result.isNull) {
        return result;
      }
    }

    // Check the node itself
    if (node.value != null) {
      currentPos.increment();
      if (currentPos.value == targetPos) {
        return nodeID;
      }
    }

    // Check right children
    for (final childID in rightChildren) {
      final result = _findNodeAtPositionRecursive(
        nodeID: childID,
        targetPos: targetPos,
        currentPos: currentPos,
      );
      if (!result.isNull) {
        return result;
      }
    }

    return FugueElementID.nullID();
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

class _CurrentPosition {
  _CurrentPosition(this.value);

  int value;

  void increment() {
    value++;
  }
}
