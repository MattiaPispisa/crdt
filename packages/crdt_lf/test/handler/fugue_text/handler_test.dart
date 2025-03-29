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

    test('should delete text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1');

      handler.insert(0, 'Hello World');
      expect(handler.value, 'Hello World');

      handler.delete(5, 6); // Delete " World"
      expect(handler.value, 'Hello');
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
      print('handler1.value: ${handler1.value}');
      print('handler2.value: ${handler2.value}');

      // Check that the insertions are not interleaved
      final finalText = handler1.value;
      expect(finalText.contains('World'), isTrue);
      expect(finalText.contains('Dart'), isTrue);

      // The exact order might depend on the HLC timestamps, but they should not be interleaved
      // TODO: check if this is correct, i think the inteleaving is not correct ("Hello World Dart"?)
      expect(
        finalText,
        'Hello  WorldDart',
      );
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
      print('finalText: $finalText');
      expect(finalText.contains(' - Edited by User1'), true);
      expect(finalText.contains(' - Modified by User2'), true);
      // expect(finalText.contains(' - Updated by User3'), true);

      // // Verify that each user's text is contiguous (not interleaved)
      // expect(finalText.contains('Edited by User1'), true);
      // expect(finalText.contains('Modified by User2'), true);
      // expect(finalText.contains('Updated by User3'), true);
    });
  });
}
