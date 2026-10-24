// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' show DAG;

import 'package:crdt_lf/src/dag/graph.dart' show DAG;

import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/utils/set.dart';

/// Directed Acyclic Graph (DAG) Node implementation for CRDT
///
/// A [DAGNode] represents a node in the [DAG]
/// that tracks the causal relationships between operations.
class DAGNode {
  /// Creates a new [DAGNode] with the given [OperationId] and parents
  DAGNode(
    this.id, {
    Set<OperationId>? parents,
  }) {
    if (parents != null) {
      parents.forEach(addParent);
    }
  }

  /// The [OperationId] of this node
  final OperationId id;

  // Each side holds `null`, one id, or a list of ids
  Object? _parents;
  Object? _children;

  /// The [OperationId]s of the parent nodes (dependencies).
  ///
  /// A new set on every call: iterate [parentIds] instead.
  Set<OperationId> get parents => _parentIds.toSet();

  /// The [OperationId]s of the child nodes.
  ///
  /// A new set on every call: iterate [childIds] instead.
  Set<OperationId> get children => _childIds.toSet();

  /// The [OperationId]s of the parent nodes, without copying.
  Iterable<OperationId> get parentIds => _parentIds;

  /// The [OperationId]s of the child nodes, without copying.
  Iterable<OperationId> get childIds => _childIds;

  Iterable<OperationId> get _parentIds => _iterate(_parents);

  Iterable<OperationId> get _childIds => _iterate(_children);

  static Iterable<OperationId> _iterate(Object? side) {
    if (side == null) {
      return const <OperationId>[];
    }
    if (side is OperationId) {
      return [side];
    }
    return side as List<OperationId>;
  }

  static Object? _add(Object? side, OperationId id) {
    if (side == null) {
      return id;
    }
    if (side is OperationId) {
      return side == id ? side : <OperationId>[side, id];
    }
    final list = side as List<OperationId>;
    if (!list.contains(id)) {
      list.add(id);
    }
    return list;
  }

  static Object? _remove(Object? side, OperationId id) {
    if (side == null) {
      return null;
    }
    if (side is OperationId) {
      return side == id ? null : side;
    }
    final list = side as List<OperationId>..remove(id);
    if (list.length == 1) {
      return list.first;
    }
    return list.isEmpty ? null : list;
  }

  static int _length(Object? side) {
    if (side == null) {
      return 0;
    }
    return side is OperationId ? 1 : (side as List<OperationId>).length;
  }

  static bool _contains(Object? side, OperationId id) {
    if (side == null) {
      return false;
    }
    return side is OperationId
        ? side == id
        : (side as List<OperationId>).contains(id);
  }

  /// Adds a parent to this node
  void addParent(OperationId parentId) {
    _parents = _add(_parents, parentId);
  }

  /// Removes a parent from this node
  void removeParent(OperationId parentId) {
    _parents = _remove(_parents, parentId);
  }

  /// Removes all parents from this node
  void removeParents() {
    _parents = null;
  }

  /// Adds a child to this node
  void addChild(OperationId childId) {
    _children = _add(_children, childId);
  }

  /// Removes a child from this node
  void removeChild(OperationId childId) {
    _children = _remove(_children, childId);
  }

  /// Checks if this node has the given parent
  bool hasParent(OperationId parentId) {
    return _contains(_parents, parentId);
  }

  /// Checks if this node has the given child
  bool hasChild(OperationId childId) {
    return _contains(_children, childId);
  }

  /// Gets the number of parents
  int get parentCount => _length(_parents);

  /// Gets the number of children
  int get childCount => _length(_children);

  /// Checks if this node is a root node (has no parents)
  bool get isRoot => _parents == null;

  /// Checks if this node is a leaf node (has no children)
  bool get isLeaf => _children == null;

  /// Returns a string representation of this node
  @override
  String toString() {
    final parentsStr = parentIds.map((p) => p.toString()).join(', ');
    final childrenStr = childIds.map((c) => c.toString()).join(', ');
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
