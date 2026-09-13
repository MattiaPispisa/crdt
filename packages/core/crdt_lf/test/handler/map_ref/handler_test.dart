import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

final doneSpec = CRDTRegisterHandler.spec<bool>('todo.done');

void main() {
  group('CRDTMapRefHandler', () {
    late CRDTDocument doc;
    late CRDTMapRefHandler root;

    setUp(() {
      doc = CRDTDocument();
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
      final docA = CRDTDocument();
      final titleA = CRDTFugueTextHandler(docA, 'title')..insert(0, 'Hello');
      final rootA = CRDTMapRefHandler(docA, 'root')..setRef('title', titleA);

      final docB = CRDTDocument();
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
        ..importSnapshot(snapshot)
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, {'title': 'Hello'});
    });
  });

  group('CRDTMapRefHandler.child', () {
    test('creates once and resolves after that', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);
      final todo = CRDTMapRefHandler(doc, 'todo');

      final first = todo.child('done', doneSpec)..set(true);
      final second = todo.child('done', doneSpec);

      expect(identical(first, second), isTrue);
      expect(second.value, isTrue);
    });

    test('rebuilds a child a peer created, instead of making a second one', () {
      // The case the ceremony used to break in silence: if the tag did not
      // match on both sides the child simply never came back.
      final author = CRDTDocument(peerId: PeerId.generate())
        ..register(doneSpec);
      CRDTMapRefHandler(author, 'todo').child('done', doneSpec).set(true);

      final peer = CRDTDocument(peerId: PeerId.generate())
        ..register(doneSpec)
        ..importChanges(author.exportChanges());

      final todo = peer.handler(CRDTMapRefHandler.spec, 'todo');
      final done = todo.child('done', doneSpec);

      expect(done.value, isTrue);
      expect(done.handlerType, doneSpec.type);
    });

    test('refuses a key holding a child of another kind', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);
      final todo = CRDTMapRefHandler(doc, 'todo')
        ..setRef('done', CRDTFugueTextHandler(doc, doc.newHandlerId()));

      expect(
        () => todo.child('done', doneSpec),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });
  });
}
