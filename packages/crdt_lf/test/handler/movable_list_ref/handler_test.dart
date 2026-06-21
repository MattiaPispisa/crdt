import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTMovableListRefHandler', () {
    late CRDTDocument doc;
    late CRDTMovableListRefHandler slides;

    setUp(() {
      doc = CRDTDocument()..registerDefaultFactories();
      slides = CRDTMovableListRefHandler(doc, 'slides');
    });

    CRDTFugueTextHandler labeled(String text) {
      return CRDTFugueTextHandler(doc, doc.newHandlerId())..insert(0, text);
    }

    test('insertRef then move reorders children preserving identity', () {
      slides
        ..insertRef(0, labeled('a'))
        ..insertRef(1, labeled('b'))
        ..insertRef(2, labeled('c'))
        ..move(2, 0);

      expect(slides.resolved, ['c', 'a', 'b']);
    });

    test('concurrent move and child edit converge without duplicates', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      final slidesA = CRDTMovableListRefHandler(docA, 'slides');
      final s0 = CRDTFugueTextHandler(docA, 's0');
      final s1 = CRDTFugueTextHandler(docA, 's1');
      slidesA
        ..insertRef(0, s0)
        ..insertRef(1, s1);
      s0.insert(0, 'zero');
      s1.insert(0, 'one');

      final docB = CRDTDocument()..registerDefaultFactories();
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
