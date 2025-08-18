import 'package:crdt_lf/crdt_lf.dart';

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
        _versionVector = VersionVector(
          Map.fromIterable(
            nodes.entries.map((e) => MapEntry(e.key.peerId, e.key.hlc)),
          ),
        );

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

    _frontiers
      ..clear()
      ..merge(Frontiers.from(frontier));

    return toRemove.length;
  }

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
      var isLowest = true;

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
