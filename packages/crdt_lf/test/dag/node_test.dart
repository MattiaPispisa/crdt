import 'package:crdt_lf/src/dag/node.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('DAGNode', () {
    late OperationId id;
    late OperationId parentId1;
    late OperationId parentId2;
    late OperationId childId1;
    late OperationId childId2;

    setUp(() {
      final author = PeerId.generate();
      final hlc = HybridLogicalClock(l: 1, c: 1);
      final hlc2 = HybridLogicalClock(l: 1, c: 2);
      final hlc3 = HybridLogicalClock(l: 1, c: 3);
      final hlc4 = HybridLogicalClock(l: 1, c: 4);

      id = OperationId(author, hlc);
      parentId1 = OperationId(author, hlc2);
      parentId2 = OperationId(author, hlc3);
      childId1 = OperationId(author, hlc4);
      childId2 = OperationId(author, HybridLogicalClock(l: 1, c: 5));
    });

    test('constructor creates node with no parents', () {
      final node = DAGNode(id);
      expect(node.id, equals(id));
      expect(node.parents, isEmpty);
      expect(node.children, isEmpty);
    });

    test('constructor creates node with parents', () {
      final parents = {parentId1, parentId2};
      final node = DAGNode(id, parents: parents);
      expect(node.id, equals(id));
      expect(node.parents, equals(parents));
      expect(node.children, isEmpty);
    });

    test('addParent adds a parent', () {
      final node = DAGNode(id)..addParent(parentId1);
      expect(node.hasParent(parentId1), isTrue);
      expect(node.parentCount, equals(1));
    });

    test('addParent does not add duplicate parent', () {
      final node = DAGNode(id)
        ..addParent(parentId1)
        ..addParent(parentId1);
      expect(node.parentCount, equals(1));
    });

    test('addChild adds a child', () {
      final node = DAGNode(id)..addChild(childId1);
      expect(node.hasChild(childId1), isTrue);
      expect(node.childCount, equals(1));
    });

    test('addChild does not add duplicate child', () {
      final node = DAGNode(id)
        ..addChild(childId1)
        ..addChild(childId1);
      expect(node.childCount, equals(1));
    });

    test('hasParent checks for parent existence', () {
      final node = DAGNode(id);
      expect(node.hasParent(parentId1), isFalse);
      node.addParent(parentId1);
      expect(node.hasParent(parentId1), isTrue);
    });

    test('hasChild checks for child existence', () {
      final node = DAGNode(id);
      expect(node.hasChild(childId1), isFalse);
      node.addChild(childId1);
      expect(node.hasChild(childId1), isTrue);
    });

    test('parentCount returns correct number of parents', () {
      final node = DAGNode(id);
      expect(node.parentCount, equals(0));
      node.addParent(parentId1);
      expect(node.parentCount, equals(1));
      node.addParent(parentId2);
      expect(node.parentCount, equals(2));
    });

    test('childCount returns correct number of children', () {
      final node = DAGNode(id);
      expect(node.childCount, equals(0));
      node.addChild(childId1);
      expect(node.childCount, equals(1));
      node.addChild(childId2);
      expect(node.childCount, equals(2));
    });

    test('isRoot returns true when node has no parents', () {
      final node = DAGNode(id);
      expect(node.isRoot, isTrue);
      node.addParent(parentId1);
      expect(node.isRoot, isFalse);
    });

    test('isLeaf returns true when node has no children', () {
      final node = DAGNode(id);
      expect(node.isLeaf, isTrue);
      node.addChild(childId1);
      expect(node.isLeaf, isFalse);
    });

    test('toString returns correct string representation', () {
      final node = DAGNode(id)
        ..addParent(parentId1)
        ..addChild(childId1);

      final expected =
          'DAGNode(id: $id, parents: [$parentId1], children: [$childId1])';
      expect(node.toString(), equals(expected));
    });

    test('should remove nodes', () {
      final node = DAGNode(id)
        ..addParent(parentId1)
        ..addChild(childId1);

      expect(node.parentCount, equals(1));
      expect(node.childCount, equals(1));

      node
        ..removeParent(parentId1)
        ..removeChild(childId1);

      expect(node.parentCount, equals(0));
      expect(node.childCount, equals(0));
    });

    test('equality works correctly', () {
      final node1 = DAGNode(id);
      final node2 = DAGNode(id);
      final node3 = DAGNode(parentId1);

      expect(node1, equals(node2));
      expect(node1, isNot(equals(node3)));

      node1.addParent(parentId1);
      expect(node1, isNot(equals(node2)));

      node2.addParent(parentId1);
      expect(node1, equals(node2));

      node1.addChild(childId1);
      expect(node1, isNot(equals(node2)));

      node2.addChild(childId1);
      expect(node1, equals(node2));
    });

    test('hashCode is consistent with equality', () {
      final node1 = DAGNode(id);
      final node2 = DAGNode(id);
      final node3 = DAGNode(parentId1);

      expect(node1.hashCode, equals(node2.hashCode));
      expect(node1.hashCode, isNot(equals(node3.hashCode)));

      node1.addParent(parentId1);
      expect(node1.hashCode, isNot(equals(node2.hashCode)));

      node2.addParent(parentId1);
      expect(node1.hashCode, equals(node2.hashCode));

      node1.addChild(childId1);
      expect(node1.hashCode, isNot(equals(node2.hashCode)));

      node2.addChild(childId1);
      expect(node1.hashCode, equals(node2.hashCode));
    });
  });
}
