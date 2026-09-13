import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

const doneType = 'todo.done';

CRDTRegisterHandler<bool> newDone(BaseCRDTDocument doc, String id) =>
    CRDTRegisterHandler<bool>(doc, id, handlerType: doneType);

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

      // B declares the kind of the child it is about to read: it arrives as a
      // ref to a handler B never opened.
      final docB = CRDTDocument()..register(CRDTFugueTextHandler.new);
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
        ..register(CRDTMapRefHandler.new)
        ..register(CRDTListRefHandler.new)
        ..register(CRDTMovableListRefHandler.new)
        ..register(CRDTFugueTextHandler.new)
        ..register(CRDTTextHandler.new)
        ..importSnapshot(snapshot)
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTMapRefHandler;
      expect(rootB.resolved, {'title': 'Hello'});
    });
  });

  group('CRDTMapRefHandler.child', () {
    test('creates once and resolves after that', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(newDone);
      final todo = CRDTMapRefHandler(doc, 'todo');

      final first = todo.child('done', newDone)..set(true);
      final second = todo.child('done', newDone);

      expect(identical(first, second), isTrue);
      expect(second.value, isTrue);
    });

    test('rebuilds a child a peer created, instead of making a second one', () {
      // The case the ceremony used to break in silence: if the tag did not
      // match on both sides the child simply never came back.
      final author = CRDTDocument(peerId: PeerId.generate())
        ..register(newDone);
      CRDTMapRefHandler(author, 'todo').child('done', newDone).set(true);

      final peer = CRDTDocument(peerId: PeerId.generate())
        ..register(newDone)
        ..importChanges(author.exportChanges());

      final todo = peer.handler(CRDTMapRefHandler.new, 'todo');
      final done = todo.child('done', newDone);

      expect(done.value, isTrue);
      expect(done.handlerType, doneType);
    });

    test('refuses a key whose kind this peer has not declared', () {
      // The child arrives as a ref and its kind is neither open nor declared,
      // so the only way to learn what it is is to build it. `child` does, then
      // compares — the wrong kind must not end up under the right id.
      final source = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(source, 'root')
          .child('title', CRDTFugueTextHandler.new)
          .insert(0, 'Intro');

      // Declares CRDTMapRefHandler by opening the root, and nothing else.
      final peer = CRDTDocument(peerId: PeerId.generate());
      final root = CRDTMapRefHandler(peer, 'root');
      peer.importChanges(source.exportChanges());

      expect(
        () => root.child('title', newDone),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });

    test('refuses a key holding a child of another kind', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(newDone);
      final todo = CRDTMapRefHandler(doc, 'todo')
        ..setRef('done', CRDTFugueTextHandler(doc, doc.newHandlerId()));

      expect(
        () => todo.child('done', newDone),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });
  });
}
