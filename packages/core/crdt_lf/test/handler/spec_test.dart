import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

/// A generic handler carries its type argument in its tag, so it needs a
/// stable one of its own.
final doneSpec = CRDTRegisterHandler.spec<bool>('todo.done');

void main() {
  group('HandlerSpec', () {
    test('holds the tag once and hands it to the builder', () {
      final doc = CRDTDocument(peerId: PeerId.generate());

      final done = doc.handler(doneSpec, 'x');

      expect(done.handlerType, doneSpec.type);
      expect(doc.registeredHandlers['x'], same(done));
    });

    test('register declares the formats, not only the factory', () {
      // A spec declares the formats too, so the type is reported before
      // anything opens a handler of it.
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);

      expect(doc.registeredHandlers, isEmpty);
      expect(
        doc.describeBuildCapabilities()[doneSpec.type],
        doneSpec.formats,
      );
    });

    test('the factory it exposes builds under the spec tag', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);

      final rebuilt = doc.resolveHandler(HandlerRef('y', doneSpec.type));

      expect(rebuilt, isA<CRDTRegisterHandler<bool>>());
      expect(rebuilt!.handlerType, doneSpec.type);
    });
  });

  group('HandlerSpec.create', () {
    test('a spec whose formats disagree with the handler is caught', () {
      // A wrong `formats` tells a peer this build reads a kind it cannot
      // decode, so the peer sends it. The app writing a generic handler is the
      // one stating them, so this is where the risk lives.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(
        () => _wrongSpec.create(doc, 'x'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a spec whose builder uses another tag is caught', () {
      // A handler built under a tag nobody addresses is a child a peer never
      // finds.
      final doc = CRDTDocument(peerId: PeerId.generate());
      final mislabelled = HandlerSpec<CRDTFugueTextHandler>(
        'not-the-tag-it-carries',
        (d, id, _) => CRDTFugueTextHandler(d, id),
        formats: CRDTFugueTextHandler.spec.formats,
      );

      expect(
        () => mislabelled.create(doc, 'x'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a spec that agrees builds normally', () {
      final doc = CRDTDocument(peerId: PeerId.generate());

      final text = CRDTFugueTextHandler.spec.create(doc, 'text');

      expect(text.handlerType, CRDTFugueTextHandler.spec.type);
    });
  });

  group('a handler declares its own type', () {
    test('the constructor registers the spec it was given', () {
      // The whole point of passing a spec instead of a bare tag: the document
      // now knows how to build that type, for an id nobody opened.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTRegisterHandler<bool>(doc, 'mine', handlerType: doneSpec.type);

      expect(doc.resolveHandler(HandlerRef('other', doneSpec.type)), isNotNull);
    });

    test('a handler with no spec leaves the document unable to rebuild it', () {
      // The flat mode, unchanged: known ids created by hand on every peer.
      final doc = CRDTDocument(peerId: PeerId.generate());
      final flat = CRDTRegisterHandler<bool>(doc, 'mine');

      expect(doc.resolveHandler(HandlerRef('other', flat.handlerType)), isNull);
    });

    test('a built-in declares itself, with nothing registered', () {
      // The built-ins pass their own spec to super, so opening one teaches the
      // document that type. Before, only registerDefaultFactories did.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(doc, 'root');

      expect(
        doc.resolveHandler(const HandlerRef('other', 'CRDTMapRefHandler')),
        isA<CRDTMapRefHandler>(),
      );
    });

    test('so a peer resolves a nested child it never opened', () {
      // What the declaration buys end to end. The receiving peer opens the
      // root by hand and nothing else; the child arrives as a ref, and the
      // type is known because the root is of that same type.
      final source = CRDTDocument(peerId: PeerId.generate());
      final child = CRDTMapRefHandler(source, 'child');
      CRDTMapRefHandler(source, 'root').setRef('chapter', child);

      final peer = CRDTDocument(peerId: PeerId.generate());
      final root = CRDTMapRefHandler(peer, 'root');
      peer.importChanges(source.exportChanges());

      expect(root.getRef('chapter'), isA<CRDTMapRefHandler>());
    });

    test('child leaves the spec behind, so the type outlives the call', () {
      // `child` holds a spec and used to drop it: the subtree it created was
      // one a reload could not rebuild.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(doc, 'root').child('done', doneSpec);

      expect(doc.resolveHandler(HandlerRef('other', doneSpec.type)), isNotNull);
    });

    test('a built-in generic declares the type from the tag alone', () {
      // The public constructor asks for a tag and nothing else; the class turns
      // it into the spec, so the type is rebuildable without the caller saying
      // how.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'l', handlerType: 'todos');

      expect(
        doc.resolveHandler(const HandlerRef('other', 'todos')),
        isA<CRDTListHandler<String>>(),
      );
    });

    test('a built-in container declares itself through handlerSpec', () {
      // The container passes no spec to its constructor: it answers one from
      // `handlerSpec`. This is the case that would break if that override were
      // lost, and it is what carries a nested tree to a peer that opened only
      // the root.
      final source = CRDTDocument(peerId: PeerId.generate());
      final child = CRDTMapRefHandler(source, 'child');
      CRDTMapRefHandler(source, 'root').setRef('chapter', child);

      final peer = CRDTDocument(peerId: PeerId.generate());
      final root = CRDTMapRefHandler(peer, 'root');
      peer.importChanges(source.exportChanges());

      expect(root.getRef('chapter'), isA<CRDTMapRefHandler>());
    });

  });

  group('one tag, one meaning', () {
    test('two handlers of one declared type are not a conflict', () {
      // Each constructor mints its own spec from the tag, so comparing them by
      // identity used to make this ordinary shape throw in debug.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(
        () {
          CRDTListHandler<String>(doc, 'active', handlerType: 'todos');
          CRDTListHandler<String>(doc, 'archived', handlerType: 'todos');
        },
        returnsNormally,
      );
    });

    test('a spec built twice from the same tag compares equal', () {
      expect(
        CRDTListHandler.spec<String>('todos'),
        CRDTListHandler.spec<String>('todos'),
      );
      expect(
        CRDTListHandler.spec<String>('todos'),
        isNot(CRDTListHandler.spec<String>('other')),
      );
    });

    test('register refuses a disposed document', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..dispose();

      expect(
        () => doc.register(CRDTListHandler.spec<String>('todos')),
        throwsA(isA<DocumentDisposedException>()),
      );
    });
  });

  group('BaseCRDTDocument.handler', () {
    test('returns the open handler instead of throwing', () {
      // Building one by hand twice throws; this is the idempotent way.
      final doc = CRDTDocument(peerId: PeerId.generate());

      final first = doc.handler(doneSpec, 'x');
      final second = doc.handler(doneSpec, 'x');

      expect(identical(first, second), isTrue);
    });

    test('refuses an id held by the same class under another tag', () {
      // The tag is what routes changes, so a Dart-type check alone would hand
      // back a handler no peer addresses as this spec's type.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTRegisterHandler<bool>(doc, 'x');

      expect(
        () => doc.handler(CRDTRegisterHandler.spec<bool>('todo.done'), 'x'),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });

    test('refuses an id held by a handler of another kind', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(doc, 'x');

      expect(
        () => doc.handler(doneSpec, 'x'),
        throwsA(isA<HandlerAlreadyRegisteredException>()),
      );
    });
  });
}

final _wrongSpec = HandlerSpec<_WrongFormats<int>>(
  'WrongFormats<T>',
  (doc, id, _) => _WrongFormats<int>(doc, id),
  formats: const HandlerFormats(
    operationKinds: {OperationType.kindInsert, OperationType.kindDelete},
    blobVersions: BlobVersionRange.single(1),
  ),
);

/// A generic handler that decodes one kind; `_wrongSpec` claims two.
final class _WrongFormats<T> extends Handler<int> {
  _WrongFormats(super.doc, this._id) : super(spec: _wrongSpec);

  final String _id;

  @override
  String get id => _id;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) => throw UnimplementedError(),
  };

  @override
  Uint8List getSnapshotState() => Uint8List(0);
}
