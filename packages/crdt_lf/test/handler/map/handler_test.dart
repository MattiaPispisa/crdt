import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTMapHandler', () {
    test('should handle basic operations', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTMapHandler<String>(doc, 'map1')

        // Set key-value pairs
        ..set('a', 'Hello')
        ..set('b', 'World')
        ..set('c', '!');

      expect(handler.value, {'a': 'Hello', 'b': 'World', 'c': '!'});
      expect(handler.value.length, 3);

      // Delete key
      handler.delete('b'); // Delete 'World'
      expect(handler.value, {'a': 'Hello', 'c': '!'});
      expect(handler.value.length, 2);

      // Delete non-existent key
      handler.delete('d'); // Should not throw
      expect(handler.value, {'a': 'Hello', 'c': '!'});
      expect(handler.value.length, 2);

      handler.update('a', 'Hello,');
      expect(handler.value, {'a': 'Hello,', 'c': '!'});
      expect(handler.value.length, 2);

      handler.update('b', 'World');
    });

    test('should handle concurrent sets', () {
      // Create two documents with their own handlers
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTMapHandler<String>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTMapHandler<String>(doc2, 'map1');

      // Initial state
      handler1.set('a', 'Hello');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, {'a': 'Hello'});
      expect(handler2.value, {'a': 'Hello'});

      // Concurrent edits
      handler1.set('b', 'World'); // doc1: {'a': 'Hello', 'b': 'World'}
      handler2.set('c', 'Dart'); // doc2: {'a': 'Hello', 'c': 'Dart'}

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler1.value.length, 3);
      expect(handler1.value['b'], 'World');
      expect(handler1.value['c'], 'Dart');
    });

    test('should handle concurrent deletions', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTMapHandler<String>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTMapHandler<String>(doc2, 'map1');

      // Initial state
      handler1
        ..set('a', 'Hello')
        ..set('b', 'World')
        ..set('c', 'Dart');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, {'a': 'Hello', 'b': 'World', 'c': 'Dart'});
      expect(handler2.value, {'a': 'Hello', 'b': 'World', 'c': 'Dart'});

      // Concurrent deletions
      handler1.delete('a'); // doc1: {'b': 'World', 'c': 'Dart'}
      handler2.delete('c'); // doc2: {'a': 'Hello', 'b': 'World'}

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler1.value, {'b': 'World'});
    });

    test('should handle concurrent set, delete and update', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTMapHandler<String>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTMapHandler<String>(doc2, 'map1');

      // Initial state: key 'a' and 'b' exists
      handler1
        ..set('a', 'Hello')
        ..set('b', 'Dart');
      doc2.importChanges(doc1.exportChanges());

      // Concurrently: doc1 deletes 'a', doc2 sets 'a' to a new value
      handler1.delete('a');
      handler2.set('a', 'Hi');

      handler1
        ..update('b', 'Dart & Flutter!')
        ..update('c', 'World!');

      // Sync changes
      doc1.importChanges(doc2.exportChanges());
      doc2.importChanges(doc1.exportChanges());

      expect(handler1.value, handler2.value);
      expect(handler1.value.keys, containsAll(['a', 'b']));
      expect(handler1.value.keys, isNot(containsAll(['c'])));
      expect(handler2.value['a'], 'Hi');
      expect(handler1.value['b'], 'Dart & Flutter!');
    });

    test('should handle generic types for values', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler = CRDTMapHandler<int>(doc, 'map1')

        // Set key-value pairs
        ..set('one', 1)
        ..set('two', 2)
        ..set('three', 3);

      expect(handler.value, {'one': 1, 'two': 2, 'three': 3});
      expect(handler['one'], 1);
      expect(handler['two'], 2);
      expect(handler['three'], 3);
    });

    test('toString returns correct string representation for empty map', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTMapHandler<String>(doc, 'map1');
      expect(handler.toString(), equals('CRDTMapHandler(map1, {})'));
    });

    test('toString returns correct string representation for map with elements',
        () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final handler = CRDTMapHandler<String>(doc, 'map1')
        ..set('a', 'Hello')
        ..set('b', 'World');
      expect(
        handler.toString(),
        equals('CRDTMapHandler(map1, {a: Hello, b: World})'),
      );
    });

    test('should use snapshot correctly', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTMapHandler<String>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTMapHandler<String>(doc2, 'map1');

      // Set values
      handler1
        ..set('a', 'Hello')
        ..set('b', 'World');
      handler2.set('c', 'Dart!');

      final changes1 = doc1.exportChanges();

      expect(
        doc1.shouldApplySnapshot(doc2.takeSnapshot()),
        isTrue,
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

      // After snapshot import and sync, states should be identical
      // and reflect the merged state before snapshotting doc2.
      expect(handler1.value, handler2.value);
      expect(handler1.value, {'a': 'Hello', 'b': 'World', 'c': 'Dart!'});

      // Further operations post-snapshot
      handler1.set('d', 'New Value');
      final changesPostSnapshot = doc1.exportChanges();
      doc2.importChanges(changesPostSnapshot);

      expect(handler1.value, handler2.value);
      expect(handler1.value['d'], 'New Value');
    });
  });
}
