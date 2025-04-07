import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTFugueTextHandler', () {
    test('should insert text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello');
      expect(handler.value, 'Hello');
      handler.insert(5, ' World');
      expect(handler.value, 'Hello World');
    });

    test('should handle empty text insertion', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, '');
      expect(handler.value, '');
      expect(handler.length, 0);
    });

    test('should delete text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello World');
      expect(handler.value, 'Hello World');

      handler.delete(5, 6); // Delete " World"
      expect(handler.value, 'Hello');
    });

    test('should handle out of bounds deletion', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello');
      handler.delete(10, 5); // Try to delete out of bounds
      expect(handler.value, 'Hello');
    });

    test('should handle value caching', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello');
      final value1 = handler.value;
      final value2 = handler.value;
      expect(identical(value1, value2), isTrue);

      // Modify the text to invalidate cache
      handler.insert(5, ' World');
      final value3 = handler.value;
      expect(identical(value1, value3), isFalse);
    });

    test('should handle value cache invalidation on document change', () {
      final doc = CRDTDocument();
      final handler1 = CRDTFugueTextHandler(doc, 'text1');
      final handler2 = CRDTFugueTextHandler(doc, 'text2');

      handler1.insert(0, 'Hello');
      final value1 = handler1.value;

      // Modify through another handler to change document version
      handler2.insert(0, 'World');

      final value2 = handler1.value;
      expect(identical(value1, value2), isFalse);
    });

    test('should maintain correct counter for element IDs', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      // Insert multiple characters
      handler.insert(0, 'Hello');
      handler.insert(5, ' World');
      handler.insert(11, '!');

      // Each character should have a unique ID
      final changes = doc.exportChanges();
      final ids =
          changes.map((c) => c.payload['newNodeID']['counter']).toList();
      expect(ids, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
    });

    test('toString returns correct string representation', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello World');
      expect(handler.toString(), equals('CRDTFugueText(text1, "Hello World")'));
    });

    test('toString truncates long text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'This is a very long text that should be truncated');
      expect(
        handler.toString(),
        equals('CRDTFugueText(text1, "This is a very long ...")'),
      );
    });

    test('should handle concurrent insertions without interleaving', () {
      // Create two documents with their own handlers
      final doc1 = CRDTDocument(
          peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'));
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');

      final doc2 = CRDTDocument(
          peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'));
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      // Initial state
      handler1.insert(0, 'Hello');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, 'Hello');
      expect(handler2.value, 'Hello');

      // Concurrent edits
      handler1.insert(5, ' World'); // doc1: "Hello World"
      handler2.insert(5, ' Dart'); // doc2: "Hello Dart"

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);

      // Check that the insertions are not interleaved
      final finalText = handler1.value;
      expect(finalText.contains(' World'), isTrue);
      expect(finalText.contains(' Dart'), isTrue);
    });

    test('should handle complex concurrent edits without interleaving', () {
      // Create three documents with their own handlers
      final doc1 = CRDTDocument(
          peerId: PeerId.parse('5cff68c5-0b34-4d9d-bd43-359db69f8fb6'));
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');

      final doc2 = CRDTDocument(
          peerId: PeerId.parse('41131068-f7f9-4938-b2f5-5f44320d8b3d'));
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      final doc3 = CRDTDocument(
          peerId: PeerId.parse('4f7db8d4-9306-49e1-a297-d0c14030a14a'));
      final handler3 = CRDTFugueTextHandler(doc3, 'text1');

      // Initial state
      handler1.insert(0, 'Shared Text');

      // Sync doc1 to doc2 and doc3
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);
      doc3.importChanges(changes1);

      expect(handler1.value, 'Shared Text');
      expect(handler2.value, 'Shared Text');
      expect(handler3.value, 'Shared Text');

      // Concurrent edits
      handler1.insert(11, ' - Edited by User1');
      handler2.insert(11, ' - Modified by User2');
      handler3.insert(11, ' - Updated by User3');

      // Sync all documents
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();
      final changes3After = doc3.exportChanges();

      doc2.importChanges(changes1After);
      doc3.importChanges(changes1After);

      doc1.importChanges(changes2After);
      doc3.importChanges(changes2After);

      doc1.importChanges(changes3After);
      doc2.importChanges(changes3After);

      // All should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler2.value, handler3.value);

      // Check that the insertions are not interleaved
      final finalText = handler1.value;
      expect(finalText.contains(' - Edited by User1'), true);
      expect(finalText.contains(' - Modified by User2'), true);
      expect(finalText.contains(' - Updated by User3'), true);

      // Verify that each user's text is contiguous (not interleaved)
      expect(finalText.contains(' - Edited by User1'), true);
      expect(finalText.contains(' - Modified by User2'), true);
      expect(finalText.contains(' - Updated by User3'), true);
    });
  });
}
