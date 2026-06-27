import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Builds a small nested tree on [doc] and returns its root.
CRDTMapRefHandler buildTree(CRDTDocument doc) {
  final root = CRDTMapRefHandler(doc, 'root');
  final title = CRDTFugueTextHandler(doc, 'title');
  final chapters = CRDTListRefHandler(doc, 'chapters');
  final intro = CRDTFugueTextHandler(doc, 'intro');
  root
    ..setRef('title', title)
    ..setRef('chapters', chapters);
  chapters.insertRef(0, intro);
  title.insert(0, 'Doc');
  intro.insert(0, 'Intro');
  return root;
}

void main() {
  group('reconstruct', () {
    test('a fresh peer rebuilds the whole tree from changes alone', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      final rootA = buildTree(docA);

      // B knows only the factories and the received changes.
      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      final rootIds = docB.roots().map((h) => h.id).toList();
      expect(rootIds, ['root']);

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, rootA.resolved);
      expect(rootB.resolved, {
        'title': 'Doc',
        'chapters': ['Intro'],
      });
    });

    test('reconstructs from a pruned snapshot via the manifest', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      buildTree(docA);
      final snapshot = docA.takeSnapshot();
      // History is pruned: no changes remain to discover types from.
      expect(docA.exportChanges(), isEmpty);

      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..importSnapshot(snapshot)
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, {
        'title': 'Doc',
        'chapters': ['Intro'],
      });
    });

    test('flat-document snapshot carries no manifest entry', () {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hello');

      final snapshot = doc.takeSnapshot();

      // The snapshot of a flat document is unchanged: only the handler id.
      expect(snapshot.data.keys, ['text']);
      expect(text.value, 'hello');

      final docB = CRDTDocument()..importSnapshot(snapshot);
      final textB = CRDTFugueTextHandler(docB, 'text');
      expect(textB.value, 'hello');
    });

    test('importing changes auto-registers handlers (no reconstruct call)', () {
      final docA = CRDTDocument()..registerDefaultFactories();
      final rootA = buildTree(docA);

      // No reconstruct(): handlers must be instantiated during import because
      // factories are registered.
      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..importChanges(docA.exportChanges());

      expect(
        docB.registeredHandlers.keys,
        containsAll(<String>['root', 'title', 'chapters', 'intro']),
      );
      expect(docB.roots().map((h) => h.id), ['root']);

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, rootA.resolved);
    });

    test('without factories, import does not auto-register (legacy)', () {
      final docA = CRDTDocument();
      final text = CRDTFugueTextHandler(docA, 'text')..insert(0, 'hi');

      final docB = CRDTDocument()..importChanges(docA.exportChanges());

      // No factory registered: the registry stays empty, classic behavior.
      expect(docB.registeredHandlers, isEmpty);

      // Reading still works by creating the handler with the matching id.
      final textB = CRDTFugueTextHandler(docB, 'text');
      expect(textB.value, text.value);
    });

    test('a generic ref with a custom handlerType reconstructs remotely', () {
      // Mirrors how the example tags its CRDTRegisterHandler<bool> so the
      // nested ref keeps working in a minified build. The factory key and the
      // handler's handlerType are the same custom tag.
      const tag = 'register/bool';
      CRDTRegisterHandler<bool> newFlag(BaseCRDTDocument d, String id) =>
          CRDTRegisterHandler<bool>(d, id, handlerType: tag);

      final docA = CRDTDocument()
        ..registerDefaultFactories()
        ..registerFactory(tag, newFlag);
      final flagA = newFlag(docA, 'flag')..set(true);
      CRDTMapRefHandler(docA, 'root').setRef('done', flagA);

      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..registerFactory(tag, newFlag)
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      final flagB = rootB.getRefAs<CRDTRegisterHandler<bool>>('done');
      expect(flagB, isNotNull);
      expect(flagB!.value, isTrue);
      expect(flagB.handlerType, tag);
    });

    test('routing follows handlerType, not the runtime class', () {
      // The handler is created with tag-A, but the remote peer only knows a
      // factory registered under tag-B, so the ref must not resolve. This
      // proves handlerType (not the runtime class) drives factory lookup.
      final docA = CRDTDocument()..registerDefaultFactories();
      final flagA = CRDTRegisterHandler<bool>(
        docA,
        'flag',
        handlerType: 'tag-A',
      )..set(true);
      CRDTMapRefHandler(docA, 'root').setRef('done', flagA);

      final docB = CRDTDocument()
        ..registerDefaultFactories()
        ..registerFactory(
          'tag-B',
          (d, id) => CRDTRegisterHandler<bool>(d, id, handlerType: 'tag-B'),
        )
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.getRef('done'), isNull);
    });
  });
}
