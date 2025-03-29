import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueNode', () {
    test('should create a valid node', () {
      final id = FugueElementID(PeerId.parse('fb089be6-cc76-4208-b7e3-bff39194b3b6'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode(
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
      final id = FugueElementID(PeerId.parse('2b7adf17-cdf2-403d-bbc1-95b1a9c516db'), 1);
      final parentId = FugueElementID.nullID();
      final node = FugueNode(
        id: id,
        value: 'a',
        parentID: parentId,
        side: FugueSide.right,
      );

      expect(node.isDeleted, false);

      node.value = null;
      expect(node.isDeleted, true);
    });
  });
}
