
import '../operation/id.dart';
import '../utils/set.dart';

/// Directed Acyclic Graph (DAG) Node implementation for CRDT
///
/// A [DAGNode] represents a node in the [DAG] that tracks the causal relationships
/// between operations.
class DAGNode {
  /// The [OperationId] of this node
  final OperationId id;

  /// The [OperationId]s of the parent nodes (dependencies)
  final Set<OperationId> parents;

  /// The [OperationId]s of the child nodes
  final Set<OperationId> children;

  /// Creates a new [DAGNode] with the given [OperationId] and parents
  DAGNode(
    this.id, {
    Set<OperationId>? parents,
  })  : parents = parents != null ? Set.from(parents) : {},
        children = {};

  /// Adds a parent to this node
  void addParent(OperationId parentId) {
    parents.add(parentId);
  }

  /// Removes a parent from this node
  void removeParent(OperationId parentId) {
    parents.remove(parentId);
  }

  /// Removes all parents from this node
  void removeParents() {
    parents.clear();
  }

  /// Adds a child to this node
  void addChild(OperationId childId) {
    children.add(childId);
  }

  /// Removes a child from this node
  void removeChild(OperationId childId) {
    children.remove(childId);
  }

  /// Checks if this node has the given parent
  bool hasParent(OperationId parentId) {
    return parents.contains(parentId);
  }

  /// Checks if this node has the given child
  bool hasChild(OperationId childId) {
    return children.contains(childId);
  }

  /// Gets the number of parents
  int get parentCount => parents.length;

  /// Gets the number of children
  int get childCount => children.length;

  /// Checks if this node is a root node (has no parents)
  bool get isRoot => parents.isEmpty;

  /// Checks if this node is a leaf node (has no children)
  bool get isLeaf => children.isEmpty;

  /// Returns a string representation of this node
  @override
  String toString() {
    final parentsStr = parents.map((p) => p.toString()).join(', ');
    final childrenStr = children.map((c) => c.toString()).join(', ');
    return 'DAGNode(id: $id, parents: [$parentsStr], children: [$childrenStr])';
  }

  /// Compares two [DAGNode]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DAGNode &&
        other.id == id &&
        setEquals(other.parents, parents) &&
        setEquals(other.children, children);
  }

  /// Returns a hash code for this [DAGNode]
  @override
  int get hashCode => Object.hash(
        id,
        Object.hashAll(parents),
        Object.hashAll(children),
      );
}
