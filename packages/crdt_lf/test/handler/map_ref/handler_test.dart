import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTMapRefHandler', () {
    late CRDTDocument doc;
    late CRDTMapRefHandler root;

    setUp(() {
      doc = CRDTDocument()..registerDefaultFactories();
      root = CRDTMapRefHandler(doc, 'root');
    });

    test('exposes a stable handlerType (minification-safe factory key)', () {
      // Pinned to the literal on purpose: a change to the tag must fail here,
      // since it is a wire/identity value shared across peers and builds.
      expect(root.handlerType, 'CRDTMapRefHandler');
      expect(HandlerRef.of(root).type, 'CRDTMapRefHandler');
    });

    test('setRef/getRef store and resolve a child handler', () {
      final title = CRDTFugueTextHandler(doc, doc.newHandlerId());
      root.setRef('title', title);
      title.insert(0, 'Hello');

      expect(root.getRef('title'), same(title));
      expect(root.childRefs(), [HandlerRef.of(title)]);
      expect(root.resolved, {'title': 'Hello'});
    });

    test('getRefAs returns the typed handler or null on mismatch', () {
      final title = CRDTFugueTextHandler(doc, doc.newHandlerId());
      root.setRef('title', title);

      expect(root.getRefAs<CRDTFugueTextHandler>('title'), same(title));
      expect(root.getRefAs<CRDTMapRefHandler>('title'), isNull);
      expect(root.getRefAs<CRDTFugueTextHandler>('missing'), isNull);
    });

    test('getRefAs asserts when given the Handler catch-all type', () {
      expect(
        () => root.getRefAs<Handler<dynamic>>('title'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('resolves a deeply nested tree', () {
      final chapter = CRDTMapRefHandler(doc, doc.newHandlerId());
      final body = CRDTFugueTextHandler(doc, doc.newHandlerId());
      root.setRef('chapter', chapter);
      chapter.setRef('body', body);
      body.insert(0, 'content');

      expect(root.resolved, {
        'chapter': {'body': 'content'},
      });
    });

    test('cycle is broken instead of recursing forever', () {
      final a = CRDTMapRefHandler(doc, doc.newHandlerId())
        ..setRef('self', root);
      root.setRef('a', a);

      // Must terminate; the reference that closes the cycle resolves to null.
      expect(root.resolved, {
        'a': {
          'self': {'a': null},
        },
      });
    });

    test('toString includes the handler id', () {
      expect(root.toString(), contains('CRDTMapRefHandler'));
    });

    test('two peers converge on a nested structure', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      final titleA = CRDTFugueTextHandler(docA, 'title')..insert(0, 'Hello');
      final rootA = CRDTMapRefHandler(docA, 'root')..setRef('title', titleA);

      final docB = CRDTDocument()..registerDefaultFactories();
      final rootB = CRDTMapRefHandler(docB, 'root');

      docB.importChanges(docA.exportChanges());

      expect(rootB.resolved, {'title': 'Hello'});
      expect(rootB.resolved, rootA.resolved);
    });

    test('snapshot round-trip with pruning preserves the nested tree', () {
      final title = CRDTFugueTextHandler(doc, 'title');
      root.setRef('title', title);
      title.insert(0, 'Hello');

      final snapshot = doc.takeSnapshot();

      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..importSnapshot(snapshot)
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, {'title': 'Hello'});
    });
  });
}
