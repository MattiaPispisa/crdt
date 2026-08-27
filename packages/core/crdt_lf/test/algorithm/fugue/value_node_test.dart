import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:test/test.dart';

void main() {
  group('FugueValueNode', () {
    late FugueElementID testId;
    late String testValue;
    late FugueValueNode<String> node;

    setUp(() {
      testId = FugueElementID(
        PeerId.parse('01b23a30-2b3c-461a-871e-0d0b8a38e7a4'),
        10,
      );
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

    test('toString returns correct format', () {
      final expected = 'FugueValueNode(id: $testId, value: $testValue)';
      expect(node.toString(), equals(expected));
    });
  });
}
