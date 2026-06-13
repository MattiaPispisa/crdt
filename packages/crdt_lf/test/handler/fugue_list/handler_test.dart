import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTFugueListHandler', () {
    test('should handle basic operations', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTFugueListHandler<String>(doc, 'list1')
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, '!');

      expect(handler.value, ['Hello', 'World', '!']);
      expect(handler.length, 3);
      expect(handler[0], 'Hello');

      // Insert in the middle
      handler.insert(1, 'Brave');
      expect(handler.value, ['Hello', 'Brave', 'World', '!']);

      // Delete elements
      handler.delete(1, 1); // Delete 'Brave'
      expect(handler.value, ['Hello', 'World', '!']);

      // Delete out of bounds is a no-op
      handler.delete(5, 1);
      expect(handler.value, ['Hello', 'World', '!']);

      // Update an element
      handler.update(0, 'Hello,');
      expect(handler.value, ['Hello,', 'World', '!']);

      // Update out of bounds is a no-op
      handler.update(9, 'nope');
      expect(handler.value, ['Hello,', 'World', '!']);
    });

    test('should work with non-string values', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueListHandler<int>(doc, 'ints')
        ..insert(0, 1)
        ..insert(1, 2)
        ..insert(2, 3);

      expect(handler.value, [1, 2, 3]);

      handler.update(1, 20);
      expect(handler.value, [1, 20, 3]);
    });

    test('should give the same result with and without incremental cache', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final a = CRDTFugueListHandler<String>(docA, 'list1')
        ..useIncrementalCacheUpdate = true
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c')
        ..delete(1, 1)
        ..update(0, 'A');

      final docB = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final b = CRDTFugueListHandler<String>(docB, 'list1')
        ..useIncrementalCacheUpdate = false
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c')
        ..delete(1, 1)
        ..update(0, 'A');

      expect(a.value, b.value);
    });

    test('should converge on concurrent insertions in the same region', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTFugueListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTFugueListHandler<String>(doc2, 'list1');

      handler1.insert(0, 'Hello');
      doc2.importChanges(doc1.exportChanges());
      expect(handler2.value, ['Hello']);

      // Concurrent edits at the same position
      handler1.insert(1, 'World');
      handler2.insert(1, 'Dart');

      final changes1 = doc1.exportChanges();
      final changes2 = doc2.exportChanges();
      doc2.importChanges(changes1);
      doc1.importChanges(changes2);

      // Both peers converge to the same order
      expect(handler1.value, handler2.value);
      expect(handler1.value.length, 3);
      expect(handler1.value.contains('World'), isTrue);
      expect(handler1.value.contains('Dart'), isTrue);
    });

    test('should not interleave concurrent runs (Fugue property)', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final h1 = CRDTFugueListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final h2 = CRDTFugueListHandler<String>(doc2, 'list1');

      // Both peers insert a run of three elements at the front concurrently
      h1
        ..insert(0, 'a1')
        ..insert(1, 'a2')
        ..insert(2, 'a3');
      h2
        ..insert(0, 'b1')
        ..insert(1, 'b2')
        ..insert(2, 'b3');

      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc2.importChanges(c1);
      doc1.importChanges(c2);

      expect(h1.value, h2.value);

      // Each peer's run must stay contiguous: no b* between two a*.
      final result = h1.value;
      final aStart = result.indexOf('a1');
      expect(result.sublist(aStart, aStart + 3), ['a1', 'a2', 'a3']);
      final bStart = result.indexOf('b1');
      expect(result.sublist(bStart, bStart + 3), ['b1', 'b2', 'b3']);
    });

    test('insertAll inserts a contiguous run atomically', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueListHandler<String>(doc, 'list1')
        ..insert(0, 'a')
        ..insert(1, 'd')
        ..insertAll(1, ['b', 'c']);

      expect(handler.value, ['a', 'b', 'c', 'd']);

      // Empty insertAll is a no-op
      handler.insertAll(0, const []);
      expect(handler.value, ['a', 'b', 'c', 'd']);
    });

    test('concurrent insertAll runs stay contiguous and converge', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final h1 = CRDTFugueListHandler<String>(doc1, 'list1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final h2 = CRDTFugueListHandler<String>(doc2, 'list1');

      // Both peers insert a run of three elements at the front concurrently
      h1.insertAll(0, ['a1', 'a2', 'a3']);
      h2.insertAll(0, ['b1', 'b2', 'b3']);

      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc2.importChanges(c1);
      doc1.importChanges(c2);

      expect(h1.value, h2.value);
      final result = h1.value;
      final aStart = result.indexOf('a1');
      expect(result.sublist(aStart, aStart + 3), ['a1', 'a2', 'a3']);
      final bStart = result.indexOf('b1');
      expect(result.sublist(bStart, bStart + 3), ['b1', 'b2', 'b3']);
    });

    test('seeds the element counter from imported update history', () {
      // doc1 produces an insert followed by an update, so its history
      // contains an update operation.
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final h1 = CRDTFugueListHandler<String>(doc1, 'list1')
        ..insert(0, 'a')
        ..update(0, 'A');

      // doc2 imports that history, then performs a *local* edit. The first
      // local edit seeds the counter by scanning the imported operations,
      // which include the update.
      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final h2 = CRDTFugueListHandler<String>(doc2, 'list1');
      doc2.importChanges(doc1.exportChanges());
      expect(h2.value, ['A']);

      h2.insert(1, 'b');
      expect(h2.value, ['A', 'b']);

      // The two peers still converge after exchanging the new change.
      doc1.importChanges(doc2.exportChanges());
      expect(h1.value, ['A', 'b']);
    });

    test('toString includes id and value', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueListHandler<String>(doc, 'list1')
        ..insert(0, 'a');
      expect(handler.toString(), contains('list1'));
      expect(handler.toString(), contains('a'));
    });

    test('should survive a snapshot round-trip', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueListHandler<String>(doc, 'list1')
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final snapshot = doc.takeSnapshot();
      handler.insert(3, '!');
      expect(handler.value, ['Hello', 'World', 'Dart', '!']);

      // Rebuild from the snapshot + later changes to exercise the
      // snapshot decode path in [_initialState].
      final reopened = CRDTDocument();
      final reopenedHandler = CRDTFugueListHandler<String>(reopened, 'list1');
      reopened
        ..mergeSnapshot(snapshot)
        ..importChanges(doc.exportChanges());
      expect(reopenedHandler.value, handler.value);
    });
  });
}
