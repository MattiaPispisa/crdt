import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// DAG (Directed Acyclic Graph) implementation for CRDT
///
/// The [DAG] tracks the causal relationships
/// between operations in the CRDT system.
/// It is used to determine which operations are causally ready to be applied.
class DAG {
  /// Creates a new DAG with the given nodes and frontiers
  DAG({
    required Map<OperationId, DAGNode> nodes,
    required Frontiers frontiers,
  })  : _nodes = nodes,
        _frontiers = frontiers,
        _versionVector = VersionVector(_versionVectorFromNodes(nodes));

  /// Creates a new empty DAG
  factory DAG.empty() {
    return DAG(
      nodes: {},
      frontiers: Frontiers(),
    );
  }

  static Map<PeerId, HybridLogicalClock> _versionVectorFromNodes(
    Map<OperationId, DAGNode> nodes,
  ) {
    final vector = <PeerId, HybridLogicalClock>{};
    for (final id in nodes.keys) {
      final current = vector[id.peerId];
      if (current == null || id.hlc.compareTo(current) > 0) {
        vector[id.peerId] = id.hlc;
      }
    }
    return vector;
  }

  /// The nodes in the [DAG], indexed by their [OperationId]
  final Map<OperationId, DAGNode> _nodes;

  /// The frontiers of the [DAG]
  final Frontiers _frontiers;

  /// Gets the number of nodes in the [DAG]
  int get nodeCount => _nodes.length;

  /// Gets the current frontiers of the [DAG]
  Set<OperationId> get frontiers => _frontiers.get();

  /// The version vector of the [DAG]
  final VersionVector _versionVector;

  /// Returns the version vector of the [DAG]
  VersionVector get versionVector => _versionVector.immutable();

  /// Checks if the [DAG] contains a [DAGNode] with the given [OperationId]
  bool containsNode(OperationId id) {
    return _nodes.containsKey(id);
  }

  /// Gets a [DAGNode] by its [OperationId]
  DAGNode? getNode(OperationId id) {
    return _nodes[id];
  }

  /// Clears the [DAG]
  void clear() {
    _nodes.clear();
    _frontiers.clear();
    _versionVector.clear();
  }

  /// Prunes the [DAG] history, keeping only nodes that
  /// happened after the given [version].
  ///
  /// Returns the number of nodes removed.
  int prune(VersionVector version) {
    final toRemove = <OperationId>[];
    final frontier = <OperationId>[];

    for (final entry in _nodes.entries) {
      final clock = version[entry.key.peerId];
      if (clock != null && entry.key.hlc.compareTo(clock) <= 0) {
        toRemove.add(entry.key);
      } else {
        if (entry.value.childCount == 0) {
          frontier.add(entry.key);
        }
      }
    }

    _removeNodes(toRemove);

    // The surviving nodes without children are the new frontier:
    // a causally-closed [version] cannot remove a child of a survivor.
    _resetFrontiersToHeads(frontier);

    return toRemove.length;
  }

  /// Resets the frontiers to the latest head per peer among [heads].
  ///
  /// Heads of different peers are concurrent and all kept; heads of the
  /// same peer are totally ordered, so only the latest one is kept.
  void _resetFrontiersToHeads(Iterable<OperationId> heads) {
    final latestByPeer = <PeerId, OperationId>{};
    for (final id in heads) {
      final latest = latestByPeer[id.peerId];
      if (latest == null || id.hlc.compareTo(latest.hlc) > 0) {
        latestByPeer[id.peerId] = id;
      }
    }
    _frontiers.reset(latestByPeer.values);
  }

  /// Removes the given nodes from the [DAG]
  ///
  /// In [DAGNode.parents] and [DAGNode.children]
  /// are removed the references to the removed nodes,
  /// then the nodes are removed from the [DAG].
  void _removeNodes(List<OperationId> operations) {
    for (final id in operations) {
      for (final parent in _nodes[id]!.parents) {
        _nodes[parent]?.removeChild(id);
      }
      for (final child in _nodes[id]!.children) {
        _nodes[child]?.removeParent(id);
      }
      _nodes.remove(id);
    }

    _versionVector.remove(operations.map((e) => e.peerId));
  }

  /// Adds a new node to the [DAG]
  ///
  /// The node's [OperationId] must not already exist in the [DAG].
  /// The node's parents must already exist in the [DAG].
  void addNode(OperationId id, Set<OperationId> deps) {
    if (_nodes.containsKey(id)) {
      throw DuplicateNodeException(
        'Node with ID $id already exists in the DAG',
      );
    }

    // Create the new node
    final node = DAGNode(id);
    _nodes.putIfAbsent(id, () => node);
    _versionVector.update(id.peerId, id.hlc);

    // Connect the node to its parents
    for (final depId in deps) {
      if (!_nodes.containsKey(depId)) {
        throw MissingDependencyException(
          'Dependency $depId does not exist in the DAG',
        );
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
    return getAncestorsOfAll([id]);
  }

  /// Gets all ancestors of a set of nodes
  ///
  /// Returns a set of all operation IDs that are ancestors of any of the
  /// given nodes, including the nodes themselves. A single traversal with a
  /// shared visited set covers all the sources.
  Set<OperationId> getAncestorsOfAll(Iterable<OperationId> ids) {
    final ancestors = <OperationId>{};
    // DFS stack
    final stack = <OperationId>[];

    for (final id in ids) {
      if (!_nodes.containsKey(id)) {
        throw ArgumentError('Node with ID $id does not exist in the DAG');
      }
      stack.add(id);
    }

    while (stack.isNotEmpty) {
      final nodeId = stack.removeLast();
      if (!ancestors.add(nodeId)) {
        continue;
      }

      for (final parentId in _nodes[nodeId]!.parents) {
        if (!ancestors.contains(parentId)) {
          stack.add(parentId);
        }
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
    final ancestorsA = getAncestorsOfAll(a);
    final ancestorsB = getAncestorsOfAll(b);

    // Find common ancestors
    final commonAncestors = ancestorsA.intersection(ancestorsB);
    if (commonAncestors.isEmpty) {
      return {};
    }

    // Find the lowest common ancestors.
    // The set of common ancestors is closed under "parent of", so an id is
    // lowest iff none of its children is itself a common ancestor.
    final lca = <OperationId>{};
    for (final id in commonAncestors) {
      final children = _nodes[id]!.children;
      final isLowest = !children.any(commonAncestors.contains);

      if (isLowest) {
        lca.add(id);
      }
    }

    return lca;
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
        _versionVector.update(id.peerId, id.hlc);
        // Connect the node to its parents
        for (final parentId in node.parents) {
          if (_nodes.containsKey(parentId)) {
            newNode.addParent(parentId);
            _nodes[parentId]!.addChild(id);
          }
        }
      }
    }

    // Recompute the frontiers from the merged graph: the nodes without
    // children are the operations not causally dominated through the graph.
    _resetFrontiersToHeads([
      for (final entry in _nodes.entries)
        if (entry.value.childCount == 0) entry.key,
    ]);
  }

  /// Returns a string representation of the DAG
  @override
  String toString() {
    final nodesStr = _nodes.values.map((n) => n.toString()).join('\n');
    return 'DAG(nodes: [\n$nodesStr\n], frontiers: $_frontiers)';
  }
}
