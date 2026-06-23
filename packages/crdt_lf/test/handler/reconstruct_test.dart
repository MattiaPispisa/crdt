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
  });
}
