import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

void main() {
  runHandlerConformanceTests(
    spec: CRDTMovableListRefHandler.spec,
    read: (list) => List.of(list.value),
    edit: (list, random, token) {
      final length = list.length;
      // A move needs a place other than the one the element holds.
      switch (length == 0 ? 0 : random.nextInt(length < 2 ? 3 : 4)) {
        case 0:
          list.insert(
            random.nextInt(length + 1),
            HandlerRef(token, CRDTFugueTextHandler.spec.type),
          );
        case 1:
          list.delete(random.nextInt(length), random.nextInt(3) + 1);
        case 2:
          list.update(
            random.nextInt(length),
            HandlerRef(token, CRDTFugueTextHandler.spec.type),
          );
        case _:
          final from = random.nextInt(length);
          list.move(from, (from + 1 + random.nextInt(length - 1)) % length);
      }
    },
  );

  group('CRDTMovableListRefHandler', () {
    late CRDTDocument doc;
    late CRDTMovableListRefHandler slides;

    setUp(() {
      doc = CRDTDocument();
      slides = CRDTMovableListRefHandler(doc, 'slides');
    });

    CRDTFugueTextHandler labeled(String text) {
      return CRDTFugueTextHandler(doc, doc.newHandlerId())..insert(0, text);
    }

    test('exposes a stable handlerType (minification-safe factory key)', () {
      expect(slides.handlerType, 'CRDTMovableListRefHandler');
    });

    test('insertRef then move reorders children preserving identity', () {
      slides
        ..insertRef(0, labeled('a'))
        ..insertRef(1, labeled('b'))
        ..insertRef(2, labeled('c'))
        ..move(2, 0);

      expect(slides.resolved, ['c', 'a', 'b']);
    });

    test('getRefAtAs returns the typed handler or null on mismatch', () {
      final a = CRDTFugueTextHandler(doc, doc.newHandlerId());
      slides.insertRef(0, a);

      expect(slides.getRefAtAs<CRDTFugueTextHandler>(0), same(a));
      expect(slides.getRefAtAs<CRDTMapRefHandler>(0), isNull);
      expect(slides.getRefAtAs<CRDTFugueTextHandler>(5), isNull);
    });

    test('a self-reference cycle resolves to null and toString works', () {
      slides.insertRef(0, slides);
      expect(slides.resolved, [
        [null],
      ]);
      expect(slides.toString(), contains('CRDTMovableListRefHandler'));
    });

    test('concurrent move and child edit converge without duplicates', () {
      final docA = CRDTDocument();
      final slidesA = CRDTMovableListRefHandler(docA, 'slides');
      final s0 = CRDTFugueTextHandler(docA, 's0');
      final s1 = CRDTFugueTextHandler(docA, 's1');
      slidesA
        ..insertRef(0, s0)
        ..insertRef(1, s1);
      s0.insert(0, 'zero');
      s1.insert(0, 'one');

      // B declares the kind of the children it is about to read: they arrive
      // as refs to handlers it never opened.
      final docB = CRDTDocument()..register(CRDTFugueTextHandler.spec);
      final slidesB = CRDTMovableListRefHandler(docB, 'slides');
      docB.importChanges(docA.exportChanges());

      // A reorders the slides; B edits the content of an existing slide.
      slidesA.move(1, 0);
      (slidesB.getRefAt(1)! as CRDTFugueTextHandler).insert(3, '-edited');

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(slidesA.resolved, slidesB.resolved);
      expect(slidesA.resolved.length, 2);
      expect(slidesA.resolved, ['one-edited', 'zero']);
    });
  });
}
