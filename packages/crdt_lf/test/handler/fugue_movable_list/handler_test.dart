import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTFugueMovableListHandler', () {
    test('basic insert / update / delete', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
      );
      final list = CRDTFugueMovableListHandler<String>(doc, 'list')
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, '!');

      expect(list.value, equals(['Hello', 'World', '!']));
      expect(list.length, equals(3));
      expect(list[1], equals('World'));

      list.update(1, 'Brave');
      expect(list.value, equals(['Hello', 'Brave', '!']));

      list.delete(0);
      expect(list.value, equals(['Brave', '!']));
    });

    test('single-element move within the same document', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final list = CRDTFugueMovableListHandler<String>(doc, 'todo')
        ..insert(0, 'buy milk')
        ..insert(1, 'water plants')
        ..insert(2, 'phone joe')
        // Move "phone joe" (index 2) to the head.
        ..move(2, 0);
      expect(list.value, equals(['phone joe', 'buy milk', 'water plants']));

      // Move it back to the tail.
      list.move(0, 2);
      expect(list.value, equals(['buy milk', 'water plants', 'phone joe']));

      // Moving the same item to the same position is a no-op.
      list.move(1, 1);
      expect(list.value, equals(['buy milk', 'water plants', 'phone joe']));

      // Out-of-range moves are no-ops.
      list.move(5, 0);
      expect(list.value, equals(['buy milk', 'water plants', 'phone joe']));
    });

    test('move out-of-range "to" clamps to the end', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c')
        ..move(0, 99);

      expect(list.value, equals(['b', 'c', 'a']));
    });

    test(
      'concurrent moves of the SAME element converge (LWW, no duplication)',
      () {
        // This is the canonical scenario from Kleppmann's paper (Figure 3):
        // both replicas move "phone joe" to a different destination; one of
        // the destinations must win, no duplication.
        final docA = CRDTDocument(
          peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
        );
        final docB = CRDTDocument(
          peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
        );
        final a = CRDTFugueMovableListHandler<String>(docA, 'l')
          ..insert(0, 'buy milk')
          ..insert(1, 'water plants')
          ..insert(2, 'phone joe');

        // Sync initial state to B.
        final b = CRDTFugueMovableListHandler<String>(docB, 'l');
        docB.importChanges(docA.exportChanges());
        expect(b.value, equals(['buy milk', 'water plants', 'phone joe']));

        // Concurrent moves of the SAME element to DIFFERENT positions.
        a.move(2, 0); // A: phone joe → index 0
        b.move(2, 1); // B: phone joe → index 1

        // Cross-sync.
        final aChanges = docA.exportChanges();
        final bChanges = docB.exportChanges();
        docA.importChanges(bChanges);
        docB.importChanges(aChanges);

        // Both replicas converge.
        expect(a.value, equals(b.value));
        // Exactly one occurrence of the moved element.
        expect(a.value.where((v) => v == 'phone joe').length, equals(1));
        expect(a.value.length, equals(3));
      },
    );

    test('concurrent moves of DIFFERENT elements both apply', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c')
        ..insert(3, 'd');

      final b = CRDTFugueMovableListHandler<String>(docB, 'l');
      docB.importChanges(docA.exportChanges());

      a.move(0, 3); // a → end on A: ['b','c','d','a']
      b.move(3, 0); // d → head on B: ['d','a','b','c']

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(a.value, equals(b.value));
      // Both 'a' and 'd' must still be present exactly once.
      expect(a.value.where((v) => v == 'a').length, equals(1));
      expect(a.value.where((v) => v == 'd').length, equals(1));
      expect(a.value.length, equals(4));
    });

    test('delete and concurrent move: deleted element stays gone', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')
        ..insert(0, 'x')
        ..insert(1, 'y')
        ..insert(2, 'z');

      final b = CRDTFugueMovableListHandler<String>(docB, 'l');
      docB.importChanges(docA.exportChanges());

      a.delete(1); // delete y on A
      b.move(1, 0); // move y to front on B

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(a.value, equals(b.value));
      expect(a.value.contains('y'), isFalse);
    });

    test('update LWW wins', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')..insert(0, 'a');
      final b = CRDTFugueMovableListHandler<String>(docB, 'l');
      docB.importChanges(docA.exportChanges());

      a.update(0, 'A');
      b.update(0, 'A2');

      final aChanges = docA.exportChanges();
      final bChanges = docB.exportChanges();
      docA.importChanges(bChanges);
      docB.importChanges(aChanges);

      expect(a.value, equals(b.value));
      // Exactly one element; value is one of the candidates.
      expect(a.value, hasLength(1));
      expect(['A', 'A2'], contains(a.value.first));
    });

    test('Fugue interleaving: concurrent inserts at same anchor', () {
      // Both peers insert a chunk at the start. Fugue keeps each peer's run
      // contiguous in the merged result, regardless of HLC ordering.
      final docA = CRDTDocument(
        peerId: PeerId.parse('00000000-0000-4000-8000-000000000001'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')
        ..insert(0, 'A1')
        ..insert(1, 'A2');
      final b = CRDTFugueMovableListHandler<String>(docB, 'l')
        ..insert(0, 'B1')
        ..insert(1, 'B2');

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(a.value, equals(b.value));
      // Each peer's run must remain contiguous.
      final merged = a.value;
      final aRun = merged.indexOf('A1');
      final aRun2 = merged.indexOf('A2');
      final bRun = merged.indexOf('B1');
      final bRun2 = merged.indexOf('B2');
      expect(aRun2, equals(aRun + 1));
      expect(bRun2, equals(bRun + 1));
    });

    test('snapshot round-trips visible list, identities and clocks', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c')
        ..move(2, 0)
        ..update(1, 'A');

      final snap = docA.takeSnapshot(pruneHistory: false);
      expect(a.value, equals(['c', 'A', 'b']));

      // Import the snapshot into an empty document and verify the list.
      final docB = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final b = CRDTFugueMovableListHandler<String>(docB, 'l');
      docB.mergeSnapshot(snap, pruneHistory: false);
      expect(b.value, equals(a.value));

      // Further edits on B continue to work.
      b
        ..insert(b.length, 'D')
        ..move(0, b.length - 1);
      expect(b.value.last, equals('c'));
      expect(b.value.contains('D'), isTrue);
    });

    test('insertAll inserts a contiguous run with Fugue non-interleaving', () {
      // Two peers both run an `insertAll` at the same anchor; each peer's
      // batch must stay contiguous in the merged result.
      final docA = CRDTDocument(
        peerId: PeerId.parse('00000000-0000-4000-8000-000000000001'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
      );
      final a = CRDTFugueMovableListHandler<String>(docA, 'l')
        ..insertAll(0, ['A1', 'A2', 'A3']);
      final b = CRDTFugueMovableListHandler<String>(docB, 'l')
        ..insertAll(0, ['B1', 'B2', 'B3']);

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(a.value, equals(b.value));
      final merged = a.value;
      // Each batch run must remain consecutive.
      final aStart = merged.indexOf('A1');
      final bStart = merged.indexOf('B1');
      expect(merged.sublist(aStart, aStart + 3), equals(['A1', 'A2', 'A3']));
      expect(merged.sublist(bStart, bStart + 3), equals(['B1', 'B2', 'B3']));
      // …and the whole batch travels in a single change.
      expect(docA.exportChanges().length, equals(2));
    });

    test('insertAll with empty iterable is a no-op', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insertAll(0, const <String>[]);
      expect(list.value, isEmpty);
      expect(doc.exportChanges(), isEmpty);
    });

    test('delete(index, count) removes a contiguous range in one op', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insertAll(0, ['a', 'b', 'c', 'd', 'e']);
      final beforeChangesCount = doc.exportChanges().length;

      list.delete(1, 3); // remove b, c, d
      expect(list.value, equals(['a', 'e']));

      // The whole range removal must produce exactly one change.
      expect(doc.exportChanges().length, equals(beforeChangesCount + 1));
    });

    test('delete(index, count) clamps to the end of the visible list', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insertAll(0, ['a', 'b', 'c'])
        ..delete(1, 99);
      expect(list.value, equals(['a']));
    });

    test('delete with non-positive count is a no-op', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insertAll(0, ['a', 'b']);
      final before = doc.exportChanges().length;
      list
        ..delete(0, 0)
        ..delete(0, -1);
      expect(list.value, equals(['a', 'b']));
      expect(doc.exportChanges().length, equals(before));
    });

    test('operation bytes round-trip via operationFactory', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..move(1, 0)
        ..update(0, 'A')
        ..delete(1);

      final changes = doc.exportChanges().sorted();
      expect(changes, isNotEmpty);
      for (final change in changes) {
        final op = list.operationFactory(change.payloadBytes());
        expect(op, isNotNull);
        expect(op!.id, equals('l'));
      }
    });
  });
}
