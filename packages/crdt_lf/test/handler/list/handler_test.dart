import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTListHandler', () {
    test('should handle basic insert and delete operations', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTListHandler<String>(doc, 'list1');

      // Insert elements
      handler.insert(0, 'Hello');
      handler.insert(1, 'World');
      handler.insert(2, '!');

      expect(handler.value, ['Hello', 'World', '!']);
      expect(handler.length, 3);

      // Delete elements
      handler.delete(1, 1); // Delete 'World'
      expect(handler.value, ['Hello', '!']);
      expect(handler.length, 2);

      // Delete out of bounds
      handler.delete(2, 1); // Should not throw
      expect(handler.value, ['Hello', '!']);
      expect(handler.length, 2);
    });

    test('should handle concurrent insertions', () {
      // Create two documents with their own handlers
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTListHandler<String>(doc2, 'list1');

      // Initial state
      handler1.insert(0, 'Hello');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, ['Hello']);
      expect(handler2.value, ['Hello']);

      // Concurrent edits
      handler1.insert(1, 'World'); // doc1: ["Hello", "World"]
      handler2.insert(1, 'Dart'); // doc2: ["Hello", "Dart"]

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler1.value.length, 3);
      expect(handler1.value.contains('World'), isTrue);
      expect(handler1.value.contains('Dart'), isTrue);
    });

    test('should handle concurrent deletions', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTListHandler<String>(doc2, 'list1');

      // Initial state
      handler1.insert(0, 'Hello');
      handler1.insert(1, 'World');
      handler1.insert(2, 'Dart');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, ['Hello', 'World', 'Dart']);
      expect(handler2.value, ['Hello', 'World', 'Dart']);

      // Concurrent deletions
      handler1.delete(0, 1); // doc1: ["World", "Dart"]
      handler2.delete(2, 1); // doc2: ["Hello", "World"]

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler1.value, ['World', 'Dart']);
    });

    test('should handle generic types', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler = CRDTListHandler<int>(doc, 'list1');

      // Insert numbers
      handler.insert(0, 1);
      handler.insert(1, 2);
      handler.insert(2, 3);

      expect(handler.value, [1, 2, 3]);
      expect(handler[0], 1);
      expect(handler[1], 2);
      expect(handler[2], 3);
    });

    test('should handle out of bounds operations gracefully', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler = CRDTListHandler<String>(doc, 'list1');

      // Insert at out of bounds index
      handler.insert(5, 'Hello');
      expect(handler.value, ['Hello']);

      // Delete at out of bounds index
      handler.delete(5, 1);
      expect(handler.value, ['Hello']);

      // Delete more elements than available
      handler.delete(0, 10);
      expect(handler.value, []);
    });

    test('should maintain causal ordering', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTListHandler<String>(doc2, 'list1');

      // Initial state
      handler1.insert(0, 'Hello');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      // Insert at same position
      handler1.insert(1, 'World');
      handler2.insert(1, 'Dart');

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // The order should be deterministic based on HLC
      final finalState = handler1.value;
      expect(finalState.length, 3);
      expect(finalState[0], 'Hello');
      // The order of 'World' and 'Dart' will be determined by HLC
      expect(finalState.contains('World'), isTrue);
      expect(finalState.contains('Dart'), isTrue);
    });

    test('toString returns correct string representation for empty list', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTListHandler<String>(doc, 'list1');
      expect(handler.toString(), equals('CRDTList(list1, [])'));
    });

    test(
        'toString returns correct string representation for list with elements',
        () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTListHandler<String>(doc, 'list1');
      handler.insert(0, 'Hello');
      handler.insert(1, 'World');
      expect(handler.toString(), equals('CRDTList(list1, [Hello, World])'));
    });

    test('should use snapshot correctly', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTListHandler<String>(doc2, 'list1');

      // Insert numbers
      handler1.insert(0, 'Hello');
      handler1.insert(1, 'World');
      handler2.insert(0, 'Dart!');

      final changes1 = doc1.exportChanges();

      expect(
        doc1.shouldApplySnapshot(doc2.takeSnapshot()),
        isFalse,
      );
      expect(
        doc2.shouldApplySnapshot(doc1.takeSnapshot()),
        isFalse,
      );

      expect(
        doc2.importChanges(changes1),
        equals(2),
      );

      expect(
        doc1.shouldApplySnapshot(
          doc2.takeSnapshot(),
        ),
        isTrue,
      );
      expect(
        doc2.shouldApplySnapshot(doc1.takeSnapshot()),
        isFalse,
      );

      expect(doc1.importSnapshot(doc2.takeSnapshot()), isTrue);
      doc1.importChanges(doc2.exportChanges());

      expect(handler2.value, handler1.value);
    });
  });
}
