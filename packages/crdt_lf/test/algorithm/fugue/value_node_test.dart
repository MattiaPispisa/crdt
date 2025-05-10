import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueValueNode', () {
    late FugueElementID testId;
    late String testValue;
    late FugueValueNode<String> node;

    setUp(() {
      testId = FugueElementID(
          PeerId.parse('01b23a30-2b3c-461a-871e-0d0b8a38e7a4'), 10,);
      testValue = 'Hello';
      node = FugueValueNode<String>(
        id: testId,
        value: testValue,
      );
    });

    test('should create a valid node', () {
      expect(node.id, testId);
      expect(node.value, testValue);
    });

    test('should serialize to JSON correctly', () {
      final json = node.toJson();

      expect(json['id'], equals(testId.toJson()));
      expect(json['value'], equals(testValue));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'id': testId.toJson(),
        'value': testValue,
      };

      final deserializedNode = FugueValueNode<String>.fromJson(json);

      expect(deserializedNode.id, equals(testId));
      expect(deserializedNode.value, equals(testValue));
    });

     test('should handle different value types in JSON', () {
        const intValue = 123;
        final intNode = FugueValueNode<int>(id: testId, value: intValue);
        final intJson = intNode.toJson();
        final deserializedIntNode = FugueValueNode<int>.fromJson(intJson);

        expect(deserializedIntNode.id, equals(testId));
        expect(deserializedIntNode.value, equals(intValue));

        const boolValue = true;
        final boolNode = FugueValueNode<bool>(id: testId, value: boolValue);
        final boolJson = boolNode.toJson();
        final deserializedBoolNode = FugueValueNode<bool>.fromJson(boolJson);

        expect(deserializedBoolNode.id, equals(testId));
        expect(deserializedBoolNode.value, equals(boolValue));
     });


    test('toString returns correct format', () {
      final expected = 'FugueValueNode(id: $testId, value: $testValue)';
      expect(node.toString(), equals(expected));
    });
  });
} 