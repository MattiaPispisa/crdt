import 'element_id.dart';
import 'node.dart';
import 'node_triple.dart';

/// Implementation of the Fugue tree for collaborative text editing
class FugueTree {
  FugueTree._({
    required Map<FugueElementID, FugueNodeTriple> nodes,
    required FugueElementID rootID,
  })  : _nodes = nodes,
        _rootID = rootID;

  /// Initializes a new empty Fugue tree
  factory FugueTree.empty() {
    // Initialize the tree with a root node
    final rootID = FugueElementID.nullID();
    final rootNode = FugueNode(
      id: rootID,
      value: null,
      parentID: FugueElementID.nullID(),
      side: FugueSide.left,
    );
    final nodes = {
      rootID: FugueNodeTriple(
        node: rootNode,
        leftChildren: [],
        rightChildren: [],
      )
    };

    return FugueTree._(
      nodes: nodes,
      rootID: rootID,
    );
  }

  /// Creates a tree from a JSON object
  factory FugueTree.fromJson(Map<String, dynamic> json) {
    // Add nodes from the JSON object
    final nodesJson = json['nodes'] as Map<String, dynamic>;
    final nodes = <FugueElementID, FugueNodeTriple>{};

    for (final entry in nodesJson.entries) {
      final id = FugueElementID.parse(entry.key);
      final triple = FugueNodeTriple.fromJson(entry.value);
      nodes[id] = triple;
    }

    return FugueTree._(
      nodes: nodes,
      rootID: FugueElementID.nullID(),
    );
  }

  /// The nodes in the tree, indexed by ID
  final Map<FugueElementID, FugueNodeTriple> _nodes;

  /// Root node ID
  final FugueElementID _rootID;

  /// Returns all non-deleted values in the correct order
  List<String> values() {
    return _traverse(_rootID);
  }

  /// Traverses the tree starting from the specified node
  ///
  /// Visits recursively the left children, then the node itself, then the right children
  /// Collects the non-deleted values (different from `⊥`)
  List<String> _traverse(FugueElementID nodeID) {
    List<String> result = [];

    if (!_nodes.containsKey(nodeID)) {
      return result;
    }

    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;

    // Recursively visit left children
    for (final childID in leftChildren) {
      result.addAll(_traverse(childID));
    }

    // Visit the node itself if not deleted
    if (node.value != null) {
      result.add(node.value!);
    }

    // Recursively visit right children
    for (final childID in rightChildren) {
      result.addAll(_traverse(childID));
    }

    return result;
  }

  /// Inserts a new [FugueNode] into the tree with [newID] and [value]
  ///
  /// [leftOrigin] is the node at position `index-1`
  ///
  /// [rightOrigin] node after [leftOrigin] in traversal order
  ///
  /// if [leftOrigin] exists, the new node will be a right child of [leftOrigin]
  /// otherwise, the new node will be a left child of [rightOrigin]
  void insert({
    required FugueElementID newID,
    required String value,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    // Determine if the new node should be a left or right child
    FugueNode newNode;

    if (!leftOrigin.isNull && _nodes.containsKey(leftOrigin)) {
      // The new node will be a right child of leftOrigin
      newNode = FugueNode(
        id: newID,
        value: value,
        parentID: leftOrigin,
        side: FugueSide.right,
      );
    } else {
      // The new node will be a left child of rightOrigin
      newNode = FugueNode(
        id: newID,
        value: value,
        parentID: rightOrigin,
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

  /// Adds a node to the tree
  void _addNodeToTree(FugueNode node) {
    final parentID = node.parentID;

    if (!_nodes.containsKey(parentID)) {
      throw Exception('Parent node not found: $parentID');
    }

    if (_nodes.containsKey(node.id)) {
      if (_nodes[node.id]!.node.value != null) {
        throw Exception('Node already exists: ${node.id}');
      }
    }

    // Create a new triple for the node
    final nodeTriple = FugueNodeTriple(
      node: node,
      leftChildren: [],
      rightChildren: [],
    );
    _nodes[node.id] = nodeTriple;

    // Update the parent's children list
    if (node.side == FugueSide.left) {
      _nodes[parentID]!.leftChildren.add(node.id);
      // Sort left children by ID
      _nodes[parentID]!.leftChildren.sort((a, b) => a.compareTo(b));
    } else {
      _nodes[parentID]!.rightChildren.add(node.id);
      // Sort right children by ID
      _nodes[parentID]!.rightChildren.sort((a, b) => a.compareTo(b));
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

    // If it has right children, the next is the first right child
    if (nodeTriple.rightChildren.isNotEmpty) {
      return nodeTriple.rightChildren.first;
    }

    // Otherwise, climb up the tree until finding a node that is a left child
    // and return its parent
    FugueElementID current = nodeID;
    while (!current.isNull) {
      final node = _nodes[current]!.node;
      if (node.side == FugueSide.left) {
        // Find the right sibling
        final parent = node.parentID;
        if (!_nodes.containsKey(parent)) {
          break;
        }

        final parentTriple = _nodes[parent]!;
        final rightSiblings = parentTriple.rightChildren;
        if (rightSiblings.isNotEmpty) {
          return rightSiblings.first;
        }
      }
      current = _nodes[current]!.node.parentID;
    }

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
    final buffer = StringBuffer();
    buffer.writeln('Tree:');
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
    buffer.writeln('$indent${node.toString()}');

    buffer.writeln('$indent Left children:');
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
