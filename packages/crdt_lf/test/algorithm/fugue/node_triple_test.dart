import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueNodeTriple', () {
    late FugueNode node;
    late List<FugueElementID> leftChildren;
    late List<FugueElementID> rightChildren;

    setUp(() {
      final nodeId = FugueElementID(PeerId.parse('ed97101d-a3f6-45a9-bf56-d5e67a0bc2e0'), 1);
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
      final triple = FugueNodeTriple(
        node: node,
        leftChildren: leftChildren,
        rightChildren: rightChildren,
      );

      expect(triple.node, equals(node));
      expect(triple.leftChildren, equals(leftChildren));
      expect(triple.rightChildren, equals(rightChildren));
    });

    test('should serialize to JSON correctly', () {
      final triple = FugueNodeTriple(
        node: node,
        leftChildren: leftChildren,
        rightChildren: rightChildren,
      );

      final json = triple.toJson();
      expect(json['node'], equals(node.toJson()));
      expect(json['leftChildren'], equals(leftChildren.map((id) => id.toJson()).toList()));
      expect(json['rightChildren'], equals(rightChildren.map((id) => id.toJson()).toList()));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'node': node.toJson(),
        'leftChildren': leftChildren.map((id) => id.toJson()).toList(),
        'rightChildren': rightChildren.map((id) => id.toJson()).toList(),
      };

      final triple = FugueNodeTriple.fromJson(json);
      expect(triple.node.id, equals(node.id));
      expect(triple.node.value, equals(node.value));
      expect(triple.node.parentID, equals(node.parentID));
      expect(triple.node.side, equals(node.side));
      expect(triple.leftChildren, equals(leftChildren));
      expect(triple.rightChildren, equals(rightChildren));
    });

    test('should handle empty children lists in JSON serialization', () {
      final triple = FugueNodeTriple(
        node: node,
        leftChildren: [],
        rightChildren: [],
      );

      final json = triple.toJson();
      expect(json['leftChildren'], isEmpty);
      expect(json['rightChildren'], isEmpty);
    });

    test('should handle empty children lists in JSON deserialization', () {
      final json = {
        'node': node.toJson(),
        'leftChildren': [],
        'rightChildren': [],
      };

      final triple = FugueNodeTriple.fromJson(json);
      expect(triple.leftChildren, isEmpty);
      expect(triple.rightChildren, isEmpty);
    });

    test('should handle single child in each list', () {
      final singleLeftChild = [leftChildren.first];
      final singleRightChild = [rightChildren.first];

      final triple = FugueNodeTriple(
        node: node,
        leftChildren: singleLeftChild,
        rightChildren: singleRightChild,
      );

      final json = triple.toJson();
      expect(json['leftChildren'], equals(singleLeftChild.map((id) => id.toJson()).toList()));
      expect(json['rightChildren'], equals(singleRightChild.map((id) => id.toJson()).toList()));

      final deserialized = FugueNodeTriple.fromJson(json);
      expect(deserialized.leftChildren, equals(singleLeftChild));
      expect(deserialized.rightChildren, equals(singleRightChild));
    });
  });
}
