import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueNode', () {
    test('should create a valid node', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      expect(node.id, id);
      expect(node.value, 'a');
      expect(node.parentID, parentId);
      expect(node.side, FugueSide.right);
      expect(node.isDeleted, false);
    });

    test('should mark node as deleted', () {
      final id = FugueElementID(
          PeerId.parse('2b7adf17-cdf2-403d-bbc1-95b1a9c516db'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      expect(node.isDeleted, false);

      node.value = null;
      expect(node.isDeleted, true);
    });

    test('should serialize to JSON correctly', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      final json = node.toJson();
      expect(json['id'], equals(id.toJson()));
      expect(json['value'], equals('a'));
      expect(json['parentID'], equals(parentId.toJson()));
      expect(json['side'], equals('right'));
    });

    test('should deserialize from JSON correctly', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final json = {
        'id': id.toJson(),
        'value': 'a',
        'parentID': parentId.toJson(),
        'side': 'right',
      };

      final node = FugueNode<String>.fromJson(json);
      expect(node.id, equals(id));
      expect(node.value, equals('a'));
      expect(node.parentID, equals(parentId));
      expect(node.side, equals(FugueSide.right));
    });

    test('should handle null value in JSON serialization', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: null,
        parentID: parentId,
        side: FugueSide.right,
      );

      final json = node.toJson();
      expect(json['value'], isNull);
    });

    test('should handle null value in JSON deserialization', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final json = {
        'id': id.toJson(),
        'value': null,
        'parentID': parentId.toJson(),
        'side': 'right',
      };

      final node = FugueNode<String>.fromJson(json);
      expect(node.value, isNull);
    });

    test('toString returns correct format', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      final expected =
          'FugueNode(id: $id, value: a, parentID: $parentId, side: ${FugueSide.right})';
      expect(node.toString(), equals(expected));
    });

    test('toString handles null value correctly', () {
      final id = FugueElementID(
          PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode<String>(
        id: id,
        value: null,
        parentID: parentId,
        side: FugueSide.right,
      );

      final expected =
          'FugueNode(id: $id, value: null, parentID: $parentId, side: ${FugueSide.right})';
      expect(node.toString(), equals(expected));
    });
  });
}
