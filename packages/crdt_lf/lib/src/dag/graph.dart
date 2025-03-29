/// DAG (Directed Acyclic Graph) implementation for CRDT
///
/// The [DAG] tracks the causal relationships between operations in the CRDT system.
/// It is used to determine which operations are causally ready to be applied.

import '../frontiers/frontiers.dart';
import '../operation/id.dart';
import 'node.dart';

/// A [DAG] tracks the causal relationships between operations in the CRDT system.
class DAG {
  /// Creates a new DAG with the given nodes and frontiers
  DAG({required Map<OperationId, DAGNode> nodes, required Frontiers frontiers})
      : _nodes = nodes,
        _frontiers = frontiers;

  /// Creates a new empty DAG
  factory DAG.empty() {
    return DAG(
      nodes: {},
      frontiers: Frontiers(),
    );
  }

  /// The nodes in the [DAG], indexed by their [OperationId]
  final Map<OperationId, DAGNode> _nodes;

  /// The frontiers of the [DAG]
  final Frontiers _frontiers;

  /// Gets the number of nodes in the [DAG]
  int get nodeCount => _nodes.length;

  /// Gets the current frontiers of the [DAG]
  Set<OperationId> get frontiers => _frontiers.get();

  /// Checks if the [DAG] contains a [DAGNode] with the given [OperationId]
  bool containsNode(OperationId id) {
    return _nodes.containsKey(id);
  }

  /// Gets a [DAGNode] by its [OperationId]
  DAGNode? getNode(OperationId id) {
    return _nodes[id];
  }

  /// Adds a new node to the [DAG]
  ///
  /// The node's [OperationId] must not already exist in the [DAG].
  /// The node's parents must already exist in the [DAG].
  void addNode(OperationId id, Set<OperationId> deps) {
    if (_nodes.containsKey(id)) {
      throw StateError('Node with ID $id already exists in the DAG');
    }

    // Create the new node
    final node = DAGNode(id);
    _nodes.putIfAbsent(id, () => node);

    // Connect the node to its parents
    for (final depId in deps) {
      if (!_nodes.containsKey(depId)) {
        throw StateError('Dependency $depId does not exist in the DAG');
      }

      node.addParent(depId);
      _nodes[depId]!.addChild(id);
    }

    // Update the frontiers
    _frontiers.update(
      newOperationId: id,
      oldDependencies: deps,
    );
  }

  /// Checks if an operation with the given dependencies is causally ready
  ///
  /// An operation is causally ready if all its dependencies exist in the DAG.
  bool isReady(Set<OperationId> deps) {
    return deps.every(_nodes.containsKey);
  }

  /// Gets all ancestors of a node
  ///
  /// Returns a set of all operation IDs that are ancestors of the given node,
  /// including the node itself.
  Set<OperationId> getAncestors(OperationId id) {
    if (!_nodes.containsKey(id)) {
      throw ArgumentError('Node with ID $id does not exist in the DAG');
    }

    final ancestors = <OperationId>{};
    final queue = <OperationId>[id];

    while (queue.isNotEmpty) {
      final nodeId = queue.removeAt(0);
      if (ancestors.contains(nodeId)) {
        continue;
      }

      ancestors.add(nodeId);

      final node = _nodes[nodeId]!;
      for (final parentId in node.parents) {
        queue.add(parentId);
      }
    }

    return ancestors;
  }

  /// Gets the lowest common ancestors (LCA) of two sets of nodes
  ///
  /// Returns a set of operation IDs that are the lowest common ancestors
  /// of the two sets of nodes.
  Set<OperationId> getLCA(Set<OperationId> a, Set<OperationId> b) {
    if (a.isEmpty || b.isEmpty) {
      return {};
    }

    // Get all ancestors of each set
    final ancestorsA = a.expand(getAncestors).toSet();
    final ancestorsB = b.expand(getAncestors).toSet();

    // Find common ancestors
    final commonAncestors = ancestorsA.intersection(ancestorsB);
    if (commonAncestors.isEmpty) {
      return {};
    }

    // Find the lowest common ancestors
    final lca = <OperationId>{};
    for (final id in commonAncestors) {
      bool isLowest = true;

      for (final otherId in commonAncestors) {
        if (id != otherId && _isAncestor(id, otherId)) {
          isLowest = false;
          break;
        }
      }

      if (isLowest) {
        lca.add(id);
      }
    }

    return lca;
  }

  /// Checks if one node is an ancestor of another
  bool _isAncestor(OperationId ancestorId, OperationId descendantId) {
    if (ancestorId == descendantId) {
      return false;
    }

    final ancestors = getAncestors(descendantId);
    return ancestors.contains(ancestorId);
  }

  /// Merges another DAG into this one
  ///
  /// All nodes from the other DAG that don't exist in this DAG are added.
  /// The frontiers are updated accordingly.
  void merge(DAG other) {
    // Add all nodes from the other DAG
    for (final entry in other._nodes.entries) {
      final id = entry.key;
      final node = entry.value;

      if (!_nodes.containsKey(id)) {
        // Create a new node
        final newNode = DAGNode(id);
        _nodes[id] = newNode;

        // Connect the node to its parents
        for (final parentId in node.parents) {
          if (_nodes.containsKey(parentId)) {
            newNode.addParent(parentId);
            _nodes[parentId]!.addChild(id);
          }
        }
      }
    }

    // Merge the frontiers
    _frontiers.merge(other._frontiers);
  }

  /// Returns a string representation of the DAG
  @override
  String toString() {
    final nodesStr = _nodes.values.map((n) => n.toString()).join('\n');
    return 'DAG(nodes: [\n$nodesStr\n], frontiers: $_frontiers)';
  }
}
