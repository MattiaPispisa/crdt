import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTORSetHandler', () {
    test('should handle basic add/remove', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final set = CRDTORSetHandler<String>(doc, 'set1')
        ..add('a')
        ..add('b');
      expect(set.value, {'a', 'b'});

      set.remove('a');
      expect(set.value, {'b'});

      // Removing non-existent value should be a no-op
      set.remove('c');
      expect(set.value, {'b'});

      // Re-adding after remove should bring it back
      set.add('a');
      expect(set.value, contains('a'));
      expect(set.contains('a'), isTrue);
      expect(set.contains('c'), isFalse);
    });

    test('should refresh clock before creating a tag', () {
      final doc = CRDTDocument();
      final hlc1 = doc.hlc;
      CRDTORSetHandler<String>(doc, 'set1').add('x');
      final change = doc.exportChanges().first.toJson();
      final payload = change['payload'] as Map<String, dynamic>;
      final tag = ORMapTag.parse(payload['tag'] as String);
      expect(tag.hlc, isNot(hlc1));
    });

    test('should handle concurrent adds', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final s1 = CRDTORSetHandler<String>(doc1, 'set1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final s2 = CRDTORSetHandler<String>(doc2, 'set1');

      s1.add('x');

      // sync one-way
      doc2.importChanges(doc1.exportChanges());
      expect(s1.value, {'x'});
      expect(s2.value, {'x'});

      // concurrent adds
      s1.add('y');
      s2.add('z');

      // sync both ways
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc1.importChanges(c2);
      doc2.importChanges(c1);

      expect(s1.value, equals(s2.value));
      expect(s1.value.length, 3);
      expect(s1.value.contains('y'), isTrue);
      expect(s1.value.contains('z'), isTrue);
    });

    test('remove only tombstones observed tags', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final set = CRDTORSetHandler<String>(doc, 'set1')
        ..add('v')
        ..add('v');
      expect(set.value, {'v'});

      // remove all tags for the value, element disappears
      set.remove('v');
      expect(set.value, isEmpty);
    });

    test('concurrent add/remove converge', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final s1 = CRDTORSetHandler<String>(doc1, 'set1');
      final s2 = CRDTORSetHandler<String>(doc2, 'set1');

      s1.add('k');
      doc2.importChanges(doc1.exportChanges());
      expect(s2.value, {'k'});

      // concurrently: s1 removes k (all known tags), s2 adds another tag for k
      s1.remove('k');
      s2.add('k');

      // sync both ways
      final c1 = doc1.exportChanges();
      final c2 = doc2.exportChanges();
      doc1.importChanges(c2);
      doc2.importChanges(c1);

      // At least one tag for 'k' remains (from s2), so 'k' is present
      expect(s1.value, equals(s2.value));
      expect(s1.value.contains('k'), isTrue);
    });

    test('snapshot import/merge with OR-Set', () {
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final s1 = CRDTORSetHandler<String>(doc1, 'set1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final s2 = CRDTORSetHandler<String>(doc2, 'set1');

      s1
        ..add('a')
        ..add('b');
      doc2.importChanges(doc1.exportChanges());
      expect(s2.value, {'a', 'b'});

      final snap = doc2.takeSnapshot();

      // Further changes on doc1
      s1.add('c');

      // Import snapshot into doc1 should be applied only if newer
      final shouldApply = doc1.shouldApplySnapshot(snap);
      expect(shouldApply, isTrue);

      // Merge snapshot (always applies) and sync both ways
      doc1
        ..mergeSnapshot(snap)
        ..importChanges(doc2.exportChanges());
      doc2.importChanges(doc1.exportChanges());

      // After merge and bidirectional sync, both should include {'a','b','c'}
      expect(s1.value, equals(s2.value));
      expect(s1.value, containsAll({'a', 'b', 'c'}));
    });
  });
}
