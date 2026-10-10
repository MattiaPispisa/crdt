import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
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
      expect(HandlerRef.of(root).type, 'CRDTORMapRefHandler');
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

    test('a put concurrent with a remove of the same key wins', () {
      final docA = CRDTDocument(peerId: PeerId.generate());
      final rootA = CRDTORMapRefHandler(docA, 'root')
        ..child('item', CRDTFugueTextHandler.spec).insert(0, 'old');

      final docB = CRDTDocument(peerId: PeerId.generate())
        ..register(CRDTFugueTextHandler.spec)
        ..importChanges(docA.exportChanges());
      final rootB = docB.handler(CRDTORMapRefHandler.spec, 'root');

      rootA.remove('item');
      final replacement = CRDTFugueTextHandler(docB, docB.newHandlerId())
        ..insert(0, 'new');
      rootB.putRef('item', replacement);

      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      expect(rootA.resolved, {'item': 'new'});
      expect(rootB.resolved, {'item': 'new'});
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

    test('a peer rebuilds the tree from a pruned snapshot', () {
      root.child('title', CRDTFugueTextHandler.spec).insert(0, 'Hello');
      final snapshot = doc.takeSnapshot();

      final docB = CRDTDocument()
        ..register(CRDTORMapRefHandler.spec)
        ..register(CRDTFugueTextHandler.spec)
        ..importSnapshot(snapshot)
        ..reconstruct();

      final rootB = docB.registeredHandlers['root']! as CRDTORMapRefHandler;
      expect(rootB.resolved, {'title': 'Hello'});
    });
  });
}
