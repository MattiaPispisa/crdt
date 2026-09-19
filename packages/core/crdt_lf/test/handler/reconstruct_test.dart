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
      final docA = CRDTDocument();
      final rootA = buildTree(docA);

      // B knows only the factories and the received changes.
      final docB = CRDTDocument()
        ..register(CRDTMapRefHandler.spec)
        ..register(CRDTListRefHandler.spec)
        ..register(CRDTMovableListRefHandler.spec)
        ..register(CRDTFugueTextHandler.spec)
        ..register(CRDTTextHandler.spec)
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
      final docA = CRDTDocument();
      buildTree(docA);
      final snapshot = docA.takeSnapshot();
      // History is pruned: no changes remain to discover types from.
      expect(docA.exportChanges(), isEmpty);

      final docB = CRDTDocument()
        ..register(CRDTMapRefHandler.spec)
        ..register(CRDTListRefHandler.spec)
        ..register(CRDTMovableListRefHandler.spec)
        ..register(CRDTFugueTextHandler.spec)
        ..register(CRDTTextHandler.spec)
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

      // A flat document writes no manifest: there is no nested handler to
      // reconstruct, so there is no {id: type} pair worth carrying.
      expect(snapshot.data.keys, isNot(contains('crdt_lf/handler-manifest')));
      expect(snapshot.data.keys, contains('text'));
      expect(text.value, 'hello');

      final docB = CRDTDocument()..importSnapshot(snapshot);
      final textB = CRDTFugueTextHandler(docB, 'text');
      expect(textB.value, 'hello');
    });

    test('a declared tree resolves as it is read, with no reconstruct', () {
      final docA = CRDTDocument();
      final rootA = buildTree(docA);

      // Importing builds nothing: a handler materializes when it is opened or
      // when someone resolves the ref that names it. Reading the root is what
      // walks the tree and brings the children in.
      final docB = CRDTDocument()
        ..register(CRDTMapRefHandler.spec)
        ..register(CRDTListRefHandler.spec)
        ..register(CRDTFugueTextHandler.spec)
        ..importChanges(docA.exportChanges());
      final rootB = CRDTMapRefHandler(docB, 'root');

      expect(rootB.resolved, rootA.resolved);
      expect(
        docB.registeredHandlers.keys,
        containsAll(<String>['root', 'title', 'chapters', 'intro']),
      );
      expect(docB.roots().map((h) => h.id), ['root']);
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

    test('a generic ref with a spec of its own reconstructs remotely', () {
      // Mirrors how the example tags its CRDTRegisterHandler<bool> so the
      // nested ref keeps working in a minified build. One spec holds the tag
      // and the builder, so the two cannot disagree.
      const tag = 'register/bool';
      final newFlagSpec = CRDTRegisterHandler.spec<bool>(tag);

      final docA = CRDTDocument();
      final flagA = newFlagSpec.create(docA, 'flag')..set(true);
      CRDTMapRefHandler(docA, 'root').setRef('done', flagA);

      final docB = CRDTDocument()
        ..register(newFlagSpec)
        ..register(CRDTMapRefHandler.spec)
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
      final docA = CRDTDocument();
      final flagA =
          CRDTRegisterHandler<bool>(docA, 'flag', handlerType: 'tag-A')
            ..set(true);
      CRDTMapRefHandler(docA, 'root').setRef('done', flagA);

      final docB = CRDTDocument()
        ..register(CRDTRegisterHandler.spec<bool>('tag-B'))
        ..register(CRDTMapRefHandler.spec)
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.getRef('done'), isNull);
    });
  });
}
