import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTORMapHandler', () {
    test('should handle basic put/remove', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final map = CRDTORMapHandler<String, int>(doc, 'map1')
        ..put('a', 1)
        ..put('b', 2);
      expect(map.value, {'a': 1, 'b': 2});

      map.remove('a');
      expect(map.value, {'b': 2});

      // Removing non-existent key should be a no-op
      map.remove('c');
      expect(map.value, {'b': 2});

      // Re-adding after remove should bring it back
      map.put('a', 10);
      expect(map.value, containsPair('a', 10));
      expect(map.containsKey('a'), isTrue);
      expect(map.containsKey('c'), isFalse);
    });

    test('should handle updates to existing keys', () {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, int>(doc, 'map1')
        ..put('x', 1)
        ..put('x', 2)
        ..put('x', 3);

      // Latest value should be present
      expect(map.value, {'x': 3});
      expect(map['x'], 3);
    });

    test('should handle concurrent puts on different keys', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final m1 = CRDTORMapHandler<String, int>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final m2 = CRDTORMapHandler<String, int>(doc2, 'map1');

      m1.put('x', 10);

      // Sync one-way
      doc2.importChanges(doc1.exportChanges());
      expect(m1.value, {'x': 10});
      expect(m2.value, {'x': 10});

      // Concurrent puts on different keys
      m1.put('y', 20);
      m2.put('z', 30);

      // Sync both ways
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc1.importChanges(c2);
      doc2.importChanges(c1);

      expect(m1.value, equals(m2.value));
      expect(m1.value.length, 3);
      expect(m1.value['y'], 20);
      expect(m1.value['z'], 30);
    });

    test('should handle concurrent puts on same key (conflict resolution)', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final m1 = CRDTORMapHandler<String, String>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final m2 = CRDTORMapHandler<String, String>(doc2, 'map1');

      // Initial sync
      m1.put('key', 'initial');
      doc2.importChanges(doc1.exportChanges());
      expect(m1.value, {'key': 'initial'});
      expect(m2.value, {'key': 'initial'});

      // Concurrent updates to the same key
      m1.put('key', 'value1');
      m2.put('key', 'value2');

      // Sync both ways
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc1.importChanges(c2);
      doc2.importChanges(c1);

      // Both should converge to the same value
      // (determined by lexicographically highest tag)
      expect(m1.value, equals(m2.value));
      expect(m1.value, containsPair('key', isA<String>()));
      expect(m1.value['key'], isIn(['value1', 'value2']));
    });

    test('remove only tombstones observed tags', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final map = CRDTORMapHandler<String, String>(doc, 'map1')
        ..put('k', 'v1')
        ..put('k', 'v2');

      // Latest value should be present
      expect(map.value, containsPair('k', 'v2'));

      // Remove all tags for the key
      map.remove('k');
      expect(map.value, isEmpty);
    });

    test('concurrent put/remove converge with add-wins semantics', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final m1 = CRDTORMapHandler<String, int>(doc1, 'map1');
      final m2 = CRDTORMapHandler<String, int>(doc2, 'map1');

      m1.put('k', 100);
      doc2.importChanges(doc1.exportChanges());
      expect(m2.value, {'k': 100});

      // Concurrently: m1 removes k, m2 adds new tag for k
      m1.remove('k');
      m2.put('k', 200);

      // Sync both ways
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc1.importChanges(c2);
      doc2.importChanges(c1);

      // At least one tag for 'k' remains (from m2), so 'k' is present
      expect(m1.value, equals(m2.value));
      expect(m1.value, containsPair('k', 200));
    });

    test('should provide map accessors', () {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, int>(doc, 'map1')
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);

      expect(map.keys, containsAll(['a', 'b', 'c']));
      expect(map.values, containsAll([1, 2, 3]));
      expect(map.entries.length, 3);
      expect(map['a'], 1);
      expect(map['b'], 2);
      expect(map['c'], 3);
      expect(map['nonexistent'], isNull);
    });

    test('snapshot import/merge with OR-Map', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final m1 = CRDTORMapHandler<String, int>(doc1, 'map1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final m2 = CRDTORMapHandler<String, int>(doc2, 'map1');

      m1
        ..put('a', 1)
        ..put('b', 2);
      doc2.importChanges(doc1.exportChanges());
      expect(m2.value, {'a': 1, 'b': 2});

      final snap = doc2.takeSnapshot();

      // Further changes on doc1
      m1.put('c', 3);

      // Import snapshot into doc1 should be applied only if newer
      final shouldApply = doc1.shouldApplySnapshot(snap);
      expect(shouldApply, isFalse);

      // Merge snapshot (always applies) and sync both ways
      doc1
        ..mergeSnapshot(snap)
        ..importChanges(doc2.exportChanges());
      doc2.importChanges(doc1.exportChanges());

      // After merge and bidirectional sync, both should include all entries
      expect(m1.value, equals(m2.value));
      expect(m1.value.keys, containsAll(['a', 'b', 'c']));
      expect(m1.value['a'], 1);
      expect(m1.value['b'], 2);
      expect(m1.value['c'], 3);
    });

    test('complex scenario with 3 peers', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final doc3 = CRDTDocument();

      final m1 = CRDTORMapHandler<String, String>(doc1, 'map1');
      final m2 = CRDTORMapHandler<String, String>(doc2, 'map1');
      final m3 = CRDTORMapHandler<String, String>(doc3, 'map1');

      // Initial puts from each peer
      m1.put('key1', 'peer1-value1');
      m2.put('key2', 'peer2-value2');
      m3.put('key3', 'peer3-value3');

      // Partial sync: 1 -> 2 -> 3 -> 1
      doc2.importChanges(doc1.exportChanges());
      doc3.importChanges(doc2.exportChanges());
      doc1.importChanges(doc3.exportChanges());

      // Check partial convergence
      expect(m1.value.length, 3);
      expect(m3.value.length, 3);

      // Concurrent updates to the same key
      m1.put('shared', 'from-peer1');
      m2.put('shared', 'from-peer2');
      m3.put('shared', 'from-peer3');

      // Full sync
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      final c3 = doc3.exportChanges();

      doc1.importChanges([...c2, ...c3]);
      doc2.importChanges([...c1, ...c3]);
      doc3.importChanges([...c1, ...c2]);

      // All should converge
      expect(m1.value, equals(m2.value));
      expect(m2.value, equals(m3.value));

      // All original keys should still be present
      expect(m1.value.keys, containsAll(['key1', 'key2', 'key3', 'shared']));

      // The shared key should have one of the three values
      // (determined by highest tag)
      expect(
        m1.value['shared'],
        isIn(['from-peer1', 'from-peer2', 'from-peer3']),
      );
    });

    test('should handle remove followed by put on same key', () {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, int>(doc, 'map1')
        ..put('key', 1)
        ..remove('key')
        ..put('key', 2);

      expect(map.value, {'key': 2});
    });

    test('should handle multiple updates and removes', () {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, String>(doc, 'map1')
        ..put('a', 'v1')
        ..put('b', 'v2')
        ..put('c', 'v3')
        ..remove('b')
        ..put('d', 'v4')
        ..put('a', 'v1-updated');

      expect(map.value, {
        'a': 'v1-updated',
        'c': 'v3',
        'd': 'v4',
      });
      expect(map.containsKey('b'), isFalse);
    });

    test('empty map operations', () {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, int>(doc, 'map1');

      expect(map.value, isEmpty);
      expect(map.keys, isEmpty);
      expect(map.values, isEmpty);
      expect(map.containsKey('any'), isFalse);
      expect(map['any'], isNull);

      // Remove on empty map should be safe
      map.remove('nonexistent');
      expect(map.value, isEmpty);
    });
  });
}

