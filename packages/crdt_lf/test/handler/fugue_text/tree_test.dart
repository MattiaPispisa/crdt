import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueTree', () {
    test('should initialize with a root node', () {
      final tree = FugueTree.empty();
      final values = tree.values();

      expect(values.isEmpty, true);
    });

    test('should insert and retrieve values', () {
      final tree = FugueTree.empty();
      final id1 = FugueElementID(PeerId.parse('4ed31065-d9e3-49cf-998a-1c156dc2b854'), 1);

      tree.insert(
        newID: id1,
        value: 'a',
        leftOrigin: tree.findNodeAtPosition(0),
        rightOrigin: FugueElementID.nullID(),
      );

      final values = tree.values();
      expect(values, ['a']);
    });

    test('should delete values', () {
      final tree = FugueTree.empty();
      final rootId = FugueElementID.nullID();
      final id1 = FugueElementID(PeerId.parse('e45b1e99-89ef-49ab-9bc1-b5da4ea3ac1e'), 1);

      tree.insert(
          newID: id1,
          value: 'a',
          leftOrigin: rootId,
          rightOrigin: FugueElementID.nullID());
      expect(tree.values(), ['a']);

      tree.delete(id1);
      expect(tree.values(), []);
    });

    test('should find node at position', () {
      final tree = FugueTree.empty();
      final rootId = FugueElementID.nullID();
      final id1 = FugueElementID(PeerId.parse('9842c3d1-e452-420b-ab4e-23c7e146b5a6'), 1);
      final id2 = FugueElementID(PeerId.parse('9842c3d1-e452-420b-ab4e-23c7e146b5a6'), 2);

      tree.insert(
          newID: id1,
          value: 'a',
          leftOrigin: rootId,
          rightOrigin: FugueElementID.nullID());
      tree.insert(
          newID: id2,
          value: 'b',
          leftOrigin: id1,
          rightOrigin: FugueElementID.nullID());

      final nodeAtPos0 = tree.findNodeAtPosition(0);
      final nodeAtPos1 = tree.findNodeAtPosition(1);

      expect(nodeAtPos0, id1);
      expect(nodeAtPos1, id2);
    });

    test('should find next node', () {
      final tree = FugueTree.empty();
      final rootId = FugueElementID.nullID();
      final id1 = FugueElementID(PeerId.parse('3ea92d73-e96d-4b0f-824e-6b37764e2f3e'), 1);
      final id2 = FugueElementID(PeerId.parse('3ea92d73-e96d-4b0f-824e-6b37764e2f3e'), 2);

      tree.insert(
          newID: id1,
          value: 'a',
          leftOrigin: rootId,
          rightOrigin: FugueElementID.nullID());
      tree.insert(
          newID: id2,
          value: 'b',
          leftOrigin: id1,
          rightOrigin: FugueElementID.nullID());

      final nextNode = tree.findNextNode(id1);
      expect(nextNode, id2);
    });
  });
}
