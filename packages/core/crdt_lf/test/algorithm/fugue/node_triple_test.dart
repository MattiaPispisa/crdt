import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/node.dart';
import 'package:crdt_lf/src/algorithm/fugue/node_triple.dart';
import 'package:test/test.dart';

/// A triple holding [left] and [right], appended in the order given.
FugueNodeTriple<String> _tripleWith(
  FugueNode<String> node, {
  List<FugueElementID> left = const [],
  List<FugueElementID> right = const [],
}) {
  final triple = FugueNodeTriple<String>(node);
  for (var i = 0; i < left.length; i++) {
    triple.insertChild(left[i], side: FugueSide.left, index: i);
  }
  for (var i = 0; i < right.length; i++) {
    triple.insertChild(right[i], side: FugueSide.right, index: i);
  }
  return triple;
}

void main() {
  group('FugueNodeTriple', () {
    late FugueNode<String> node;
    late List<FugueElementID> leftChildren;
    late List<FugueElementID> rightChildren;

    setUp(() {
      final nodeId = FugueElementID(
        PeerId.parse('ed97101d-a3f6-45a9-bf56-d5e67a0bc2e0'),
        1,
      );
      final parentId = FugueElementID.nullID();
      node = FugueNode<String>(
        id: nodeId,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      leftChildren = [
        FugueElementID(PeerId.parse('698f2cff-83ec-482f-90cf-b60ba139dc16'), 1),
        FugueElementID(PeerId.parse('582333db-ad39-4e52-a276-d4d89a80c88c'), 2),
      ];

      rightChildren = [
        FugueElementID(PeerId.parse('cdd89983-aaf7-40ed-80be-ba8427b95812'), 1),
        FugueElementID(PeerId.parse('ccadc3f2-7045-4617-9e44-a45475432ed7'), 2),
      ];
    });

    test('should create a valid node triple', () {
      final triple = _tripleWith(
        node,
        left: leftChildren,
        right: rightChildren,
      );

      expect(triple.node, equals(node));
      expect(triple.leftChildren, equals(leftChildren));
      expect(triple.rightChildren, equals(rightChildren));
    });

    test('a fresh triple has no children on either side', () {
      final triple = FugueNodeTriple<String>(node);

      expect(triple.leftChildren, isEmpty);
      expect(triple.rightChildren, isEmpty);
    });

    // The empty case is a shared constant, so a leaf costs no list at all.
    // Two triples must therefore hand out the very same object, and adding a
    // child to one must not be visible from the other.
    test('leaves share the empty list, and the first child breaks it apart',
        () {
      final one = FugueNodeTriple<String>(node);
      final other = FugueNodeTriple<String>(node);

      expect(identical(one.leftChildren, other.leftChildren), isTrue);
      expect(identical(one.rightChildren, other.rightChildren), isTrue);

      one.insertChild(leftChildren.first, side: FugueSide.left, index: 0);

      expect(one.leftChildren, equals([leftChildren.first]));
      expect(other.leftChildren, isEmpty);
      // The side that stayed empty is untouched.
      expect(one.rightChildren, isEmpty);
    });

    test('insertChild puts a child at the index it is given', () {
      final triple = _tripleWith(node, left: leftChildren);
      final middle = FugueElementID(
        PeerId.parse('11111111-1111-4111-8111-111111111111'),
        3,
      );

      triple.insertChild(middle, side: FugueSide.left, index: 1);

      expect(
        triple.leftChildren,
        equals([leftChildren[0], middle, leftChildren[1]]),
      );
    });

    test('should serialize to JSON correctly', () {
      final triple = _tripleWith(
        node,
        left: leftChildren,
        right: rightChildren,
      );

      final json = triple.toJson();
      expect(json['node'], equals(node.toJson()));
      expect(
        json['leftChildren'],
        equals(leftChildren.map((id) => id.toJson()).toList()),
      );
      expect(
        json['rightChildren'],
        equals(rightChildren.map((id) => id.toJson()).toList()),
      );
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'node': node.toJson(),
        'leftChildren': leftChildren.map((id) => id.toJson()).toList(),
        'rightChildren': rightChildren.map((id) => id.toJson()).toList(),
      };

      final triple = FugueNodeTriple<String>.fromJson(json);
      expect(triple.node.id, equals(node.id));
      expect(triple.node.value, equals(node.value));
      expect(triple.node.parentID, equals(node.parentID));
      expect(triple.node.side, equals(node.side));
      expect(triple.leftChildren, equals(leftChildren));
      expect(triple.rightChildren, equals(rightChildren));
    });

    test('should handle empty children lists in JSON serialization', () {
      final triple = FugueNodeTriple<String>(node);

      final json = triple.toJson();
      expect(json['leftChildren'], isEmpty);
      expect(json['rightChildren'], isEmpty);
    });

    test('should handle empty children lists in JSON deserialization', () {
      final json = {
        'node': node.toJson(),
        'leftChildren': <dynamic>[],
        'rightChildren': <dynamic>[],
      };

      final triple = FugueNodeTriple<String>.fromJson(json);
      expect(triple.leftChildren, isEmpty);
      expect(triple.rightChildren, isEmpty);
      // A side that came back empty still allocates nothing.
      final fresh = FugueNodeTriple<String>(node);
      expect(identical(triple.leftChildren, fresh.leftChildren), isTrue);
    });

    test('should handle single child in each list', () {
      final singleLeftChild = [leftChildren.first];
      final singleRightChild = [rightChildren.first];

      final triple = _tripleWith(
        node,
        left: singleLeftChild,
        right: singleRightChild,
      );

      final json = triple.toJson();
      expect(
        json['leftChildren'],
        equals(singleLeftChild.map((id) => id.toJson()).toList()),
      );
      expect(
        json['rightChildren'],
        equals(singleRightChild.map((id) => id.toJson()).toList()),
      );

      final deserialized = FugueNodeTriple<String>.fromJson(json);
      expect(deserialized.leftChildren, equals(singleLeftChild));
      expect(deserialized.rightChildren, equals(singleRightChild));
    });
  });
}
