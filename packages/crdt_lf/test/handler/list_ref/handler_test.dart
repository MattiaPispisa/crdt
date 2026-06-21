import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTListRefHandler', () {
    late CRDTDocument doc;
    late CRDTListRefHandler list;

    setUp(() {
      doc = CRDTDocument()..registerDefaultFactories();
      list = CRDTListRefHandler(doc, 'list');
    });

    test('insertRef/getRefAt store and resolve children in order', () {
      final a = CRDTFugueTextHandler(doc, doc.newHandlerId());
      final b = CRDTFugueTextHandler(doc, doc.newHandlerId());
      list
        ..insertRef(0, a)
        ..insertRef(1, b);
      a.insert(0, 'A');
      b.insert(0, 'B');

      expect(list.getRefAt(0), same(a));
      expect(list.getRefAt(1), same(b));
      expect(list.getRefAt(5), isNull);
      expect(list.resolved, ['A', 'B']);
    });

    test('a self-reference cycle resolves to null and toString works', () {
      list.insertRef(0, list);
      expect(list.resolved, [
        [null],
      ]);
      expect(list.toString(), contains('CRDTListRefHandler'));
    });

    test('concurrent insertions in the same region converge', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      final listA = CRDTListRefHandler(docA, 'list');
      final first = CRDTFugueTextHandler(docA, 'first');
      listA.insertRef(0, first);
      first.insert(0, 'first');

      final docB = CRDTDocument()..registerDefaultFactories();
      final listB = CRDTListRefHandler(docB, 'list');
      docB.importChanges(docA.exportChanges());

      // Concurrent inserts at the same position.
      final fromA = CRDTFugueTextHandler(docA, 'a');
      listA.insertRef(1, fromA);
      fromA.insert(0, 'a');

      final fromB = CRDTFugueTextHandler(docB, 'b');
      listB.insertRef(1, fromB);
      fromB.insert(0, 'b');

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(listA.resolved, listB.resolved);
      expect(listA.resolved.length, 3);
    });
  });
}
