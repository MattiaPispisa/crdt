import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

void main() {
  runHandlerConformanceTests(
    spec: CRDTORMapRefHandler.spec,
    read: (map) => Map.of(map.value),
    edit: (map, random, token) {
      final present = map.keys.toList();
      if (present.isEmpty || random.nextBool()) {
        map.put(
          'k${random.nextInt(8)}',
          HandlerRef(token, CRDTFugueTextHandler.spec.type),
        );
      } else {
        map.remove(present[random.nextInt(present.length)]);
      }
    },
  );

  group('CRDTORMapRefHandler', () {
    late CRDTDocument doc;
    late CRDTORMapRefHandler root;

    setUp(() {
      doc = CRDTDocument();
      root = CRDTORMapRefHandler(doc, 'root');
    });

    test('exposes a stable handlerType', () {
      // Pinned to the literal: the tag is a wire value shared across peers.
      expect(root.handlerType, 'CRDTORMapRefHandler');
    });

    test('putRef/getRef store and resolve a child handler', () {
      final title = CRDTFugueTextHandler(doc, doc.newHandlerId());
      root.putRef('title', title);
      title.insert(0, 'Hello');

      expect(root.getRef('title'), same(title));
      expect(root.getRef('missing'), isNull);
      expect(root.getRefAs<CRDTFugueTextHandler>('title'), same(title));
      expect(root.getRefAs<CRDTORMapRefHandler>('title'), isNull);
      expect(root.childRefs(), [HandlerRef.of(title)]);
      expect(root.resolved, {'title': 'Hello'});
      expect(root.toString(), contains('CRDTORMapRefHandler'));
    });

    test('child creates once, then hands back the same child', () {
      final first = root.child('title', CRDTFugueTextHandler.spec)
        ..insert(0, 'Hi');
      final second = root.child('title', CRDTFugueTextHandler.spec);

      expect(second, same(first));
      expect(root.resolved, {'title': 'Hi'});
    });

    test('child refuses a key holding a child of another kind', () {
      root.child('title', CRDTFugueTextHandler.spec);

      expect(
        () => root.child('title', CRDTMapRefHandler.spec),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });

    test('removeChild removes the key and deletes the child', () {
      final title = root.child('title', CRDTFugueTextHandler.spec)
        ..insert(0, 'Hello');

      root
        ..removeChild('title')
        ..removeChild('missing');

      expect(root.value, isEmpty);
      expect(root.resolved, isEmpty);
      expect(title.isDeleted, isTrue);
    });

    group('two children put concurrently under one key', () {
      late CRDTFugueTextHandler mine;
      late CRDTFugueTextHandler theirs;

      setUp(() {
        final peer = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(doc.exportChanges());
        theirs = peer
            .handler(CRDTORMapRefHandler.spec, root.id)
            .child('k', CRDTFugueTextHandler.spec);
        mine = root.child('k', CRDTFugueTextHandler.spec);
        doc.importChanges(peer.exportChanges());
      });

      test('are both children, so neither is a root', () {
        doc.handler(CRDTFugueTextHandler.spec, theirs.id);

        expect(root.childRefs().map((ref) => ref.id), {mine.id, theirs.id});
        expect(doc.roots(), [root]);
      });

      test('are both deleted with their container', () {
        doc.deleteHandler(root);

        expect(doc.isDeleted(mine.id), isTrue);
        expect(doc.isDeleted(theirs.id), isTrue);
      });

      test('are both deleted by removeChild', () {
        root.removeChild('k');

        expect(doc.isDeleted(mine.id), isTrue);
        expect(doc.isDeleted(theirs.id), isTrue);
      });
    });
  });
}
