import 'element_id.dart';
import 'node.dart';
import 'node_triple.dart';

/// Implementation of the Fugue tree for collaborative text editing
class FugueTree {
  /// Constructor that initializes a new empty Fugue tree
  FugueTree() {
    // Initialize the tree with a root node
    final rootID = FugueElementID.nullID();
    final rootNode = FugueNode(rootID, null, FugueElementID.nullID(), FugueSide.left);
    _nodes[rootID] = FugueNodeTriple(rootNode, [], []);
  }
  
  /// The nodes in the tree, indexed by ID
  final Map<FugueElementID, FugueNodeTriple> _nodes = {};
  
  /// Root node ID
  final FugueElementID _rootID = FugueElementID.nullID();
  
  /// Returns all non-deleted values in the correct order
  List<String> values() {
    return _traverse(_rootID);
  }
  
  /// Traverses the tree starting from the specified node
  List<String> _traverse(FugueElementID nodeID) {
    List<String> result = [];
    
    if (!_nodes.containsKey(nodeID)) return result;
    
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
  
  /// Inserts a new node into the tree
  void insert(FugueElementID newID, String value, FugueElementID leftOrigin, FugueElementID rightOrigin) {
    // Determine if the new node should be a left or right child
    FugueNode newNode;
    
    if (!rightOrigin.isNull && _nodes.containsKey(rightOrigin)) {
      // The new node will be a left child of rightOrigin
      newNode = FugueNode(newID, value, rightOrigin, FugueSide.left);
    } else {
      // The new node will be a right child of leftOrigin
      newNode = FugueNode(newID, value, leftOrigin, FugueSide.right);
    }
    
    // Add the node to the tree
    _addNodeToTree(newNode);
  }
  
  /// Deletes a node from the tree (marks it as deleted)
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
    
    // Create a new triple for the node
    final nodeTriple = FugueNodeTriple(node, [], []);
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
    int currentPos = -1;
    return _findNodeAtPositionHelper(_rootID, position, currentPos);
  }
  
  /// Recursive helper to find the node at the specified position
  FugueElementID _findNodeAtPositionHelper(FugueElementID nodeID, int targetPos, int currentPos) {
    if (!_nodes.containsKey(nodeID)) return FugueElementID.nullID();
    
    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;
    
    // Check left children
    for (final childID in leftChildren) {
      final result = _findNodeAtPositionHelper(childID, targetPos, currentPos);
      if (!result.isNull) {
        return result;
      }
      currentPos += _countVisibleNodes(childID);
    }
    
    // Check the node itself
    if (node.value != null) {
      currentPos++;
      if (currentPos == targetPos) {
        return nodeID;
      }
    }
    
    // Check right children
    for (final childID in rightChildren) {
      final result = _findNodeAtPositionHelper(childID, targetPos, currentPos);
      if (!result.isNull) {
        return result;
      }
      currentPos += _countVisibleNodes(childID);
    }
    
    return FugueElementID.nullID();
  }
  
  /// Counts visible nodes in the subtree rooted at nodeID
  int _countVisibleNodes(FugueElementID nodeID) {
    return _traverse(nodeID).length;
  }
  
  /// Finds the next node after nodeID in the traversal
  FugueElementID findNextNode(FugueElementID nodeID) {
    if (!_nodes.containsKey(nodeID)) return FugueElementID.nullID();
    
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
        if (!_nodes.containsKey(parent)) break;
        
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
  
  /// Creates a tree from a JSON object
  factory FugueTree.fromJson(Map<String, dynamic> json) {
    final tree = FugueTree();
    
    // Clear the tree (remove the default root node)
    tree._nodes.clear();
    
    // Add nodes from the JSON object
    final nodesJson = json['nodes'] as Map<String, dynamic>;
    for (final entry in nodesJson.entries) {
      final id = FugueElementID.parse(entry.key);
      final triple = FugueNodeTriple.fromJson(entry.value);
      tree._nodes[id] = triple;
    }
    
    return tree;
  }
  
  /// Prints the tree for debugging
  void printTree() {
    print('Tree:');
    _printNodeAndChildren(_rootID, 0);
  }
  
  /// Helper to print a node and its children
  void _printNodeAndChildren(FugueElementID nodeID, int depth) {
    if (!_nodes.containsKey(nodeID)) return;
    
    final nodeTriple = _nodes[nodeID]!;
    final node = nodeTriple.node;
    final leftChildren = nodeTriple.leftChildren;
    final rightChildren = nodeTriple.rightChildren;
    
    final indent = '  ' * depth;
    print('$indent${node.toString()}');
    
    print('$indent Left children:');
    for (final childID in leftChildren) {
      _printNodeAndChildren(childID, depth + 1);
    }
    
    print('$indent Right children:');
    for (final childID in rightChildren) {
      _printNodeAndChildren(childID, depth + 1);
    }
  }
}
