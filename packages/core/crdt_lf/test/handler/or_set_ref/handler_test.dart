import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTORSetRefHandler', () {
    late CRDTDocument doc;
    late CRDTORSetRefHandler tags;

    setUp(() {
      doc = CRDTDocument();
      tags = CRDTORSetRefHandler(doc, 'tags');
    });

    test('exposes a stable handlerType', () {
      // Pinned to the literal: the tag is a wire value shared across peers.
      expect(tags.handlerType, 'CRDTORSetRefHandler');
      expect(HandlerRef.of(tags).type, 'CRDTORSetRefHandler');
    });

    test('addRef/removeRef/containsRef manage the references', () {
      final a = CRDTFugueTextHandler(doc, 'a')..insert(0, 'A');
      final b = CRDTFugueTextHandler(doc, 'b')..insert(0, 'B');
      tags
        ..addRef(b)
        ..addRef(a);

      expect(tags.containsRef(a), isTrue);
      expect(tags.children, [a, b]);
      expect(tags.resolved, ['A', 'B']);

      tags.removeRef(a);

      expect(tags.containsRef(a), isFalse);
      expect(a.isDeleted, isFalse);
      expect(tags.resolved, ['B']);

      // A kind this document does not know resolves to nothing.
      tags.add(const HandlerRef('ghost', 'Unknown'));
      expect(tags.children, [b]);
      expect(tags.resolved, ['B', null]);
      expect(tags.toString(), contains('CRDTORSetRefHandler'));
    });

    test('addChild always adds a new child', () {
      final first = tags.addChild(CRDTFugueTextHandler.spec);
      final second = tags.addChild(CRDTFugueTextHandler.spec);

      expect(first.id, isNot(second.id));
      expect(tags.value, hasLength(2));
    });

    test('removeChild removes the reference and deletes the child', () {
      final child = tags.addChild(CRDTFugueTextHandler.spec)..insert(0, 'x');

      tags.removeChild(child);

      expect(tags.value, isEmpty);
      expect(child.isDeleted, isTrue);
    });

    test('two peers resolve to the same list, whatever the order of adds', () {
      final docA = CRDTDocument(peerId: PeerId.generate())
        ..register(CRDTFugueTextHandler.spec);
      final docB = CRDTDocument(peerId: PeerId.generate())
        ..register(CRDTFugueTextHandler.spec);
      final setA = CRDTORSetRefHandler(docA, 'tags');
      final setB = CRDTORSetRefHandler(docB, 'tags');

      for (var i = 0; i < 5; i++) {
        setA.addChild(CRDTFugueTextHandler.spec).insert(0, 'a$i');
        setB.addChild(CRDTFugueTextHandler.spec).insert(0, 'b$i');
      }
      // Warm caches fold the remote adds incrementally, in arrival order.
      expect(setA.value, hasLength(5));
      expect(setB.value, hasLength(5));

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(setA.resolved, hasLength(10));
      expect(setA.resolved, setB.resolved);
    });
  });
}
