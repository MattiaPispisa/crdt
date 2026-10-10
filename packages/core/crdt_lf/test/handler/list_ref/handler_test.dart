import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

void main() {
  runHandlerConformanceTests(
    spec: CRDTListRefHandler.spec,
    read: (list) => List.of(list.value),
    edit: (list, random, token) {
      final length = list.length;
      switch (length == 0 ? 0 : random.nextInt(3)) {
        case 0:
          list.insert(
            random.nextInt(length + 1),
            HandlerRef(token, CRDTFugueTextHandler.spec.type),
          );
        case 1:
          list.delete(random.nextInt(length), random.nextInt(3) + 1);
        case _:
          list.update(
            random.nextInt(length),
            HandlerRef(token, CRDTFugueTextHandler.spec.type),
          );
      }
    },
  );

  group('CRDTListRefHandler', () {
    late CRDTDocument doc;
    late CRDTListRefHandler list;

    setUp(() {
      doc = CRDTDocument();
      list = CRDTListRefHandler(doc, 'list');
    });

    test('exposes a stable handlerType (minification-safe factory key)', () {
      expect(list.handlerType, 'CRDTListRefHandler');
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

    test('getRefAtAs returns the typed handler or null on mismatch', () {
      final a = CRDTFugueTextHandler(doc, doc.newHandlerId());
      list.insertRef(0, a);

      expect(list.getRefAtAs<CRDTFugueTextHandler>(0), same(a));
      expect(list.getRefAtAs<CRDTMapRefHandler>(0), isNull);
      expect(list.getRefAtAs<CRDTFugueTextHandler>(5), isNull);
    });

    test('a self-reference cycle resolves to null and toString works', () {
      list.insertRef(0, list);
      expect(list.resolved, [
        [null],
      ]);
      expect(list.toString(), contains('CRDTListRefHandler'));
    });
  });

  group('CRDTListRefHandler.insertChild', () {
    test('adds a new child every time, unlike a keyed child', () {
      // An insert adds an element, so there is no key to be idempotent about.
      final doc = CRDTDocument(peerId: PeerId.generate());
      final blocks = CRDTListRefHandler(doc, 'blocks');

      final first = blocks.insertChild(0, CRDTFugueTextHandler.spec)
        ..insert(0, 'a');
      final second = blocks.insertChild(1, CRDTFugueTextHandler.spec)
        ..insert(0, 'b');

      expect(identical(first, second), isFalse);
      expect(blocks.value, hasLength(2));
      expect(blocks.getRefAtAs<CRDTFugueTextHandler>(0)?.value, 'a');
      expect(blocks.getRefAtAs<CRDTFugueTextHandler>(1)?.value, 'b');
    });
  });
}
