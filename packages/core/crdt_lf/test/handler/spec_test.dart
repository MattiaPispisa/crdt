import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

const doneType = 'todo.done';

final doneSpec = CRDTRegisterHandler.spec<bool>(doneType);

void main() {
  group('a handler names its own kind', () {
    test('so the document can rebuild it under another id', () {
      // The whole reason a tag is asked for: the document now knows how to
      // build that kind, for an id nobody opened.
      final doc = CRDTDocument(peerId: PeerId.generate());
      doneSpec.create(doc, 'mine');

      expect(
        doc.resolveHandler(const HandlerRef('other', doneType)),
        isNotNull,
      );
    });

    test('a built-in names its own, with nothing registered', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(doc, 'root');

      expect(
        doc.resolveHandler(const HandlerRef('other', 'CRDTMapRefHandler')),
        isA<CRDTMapRefHandler>(),
      );
    });

    test('a kind nobody opened or declared resolves to nothing', () {
      // The rule, and it holds for every kind alike — the ones this package
      // ships included. A peer reads what it has been set up for.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(doc.resolveHandler(const HandlerRef('x', doneType)), isNull);
      expect(
        doc.resolveHandler(const HandlerRef('x', 'CRDTFugueTextHandler')),
        isNull,
      );
    });

    test('so a peer resolves a nested child of a kind it has open', () {
      // What naming the kind buys end to end: the child arrives as a ref, and
      // the receiving peer can build it because the root it opened is of that
      // same kind.
      final source = CRDTDocument(peerId: PeerId.generate());
      final child = CRDTMapRefHandler(source, 'child');
      CRDTMapRefHandler(source, 'root').setRef('chapter', child);

      final peer = CRDTDocument(peerId: PeerId.generate());
      final root = CRDTMapRefHandler(peer, 'root');
      peer.importChanges(source.exportChanges());

      expect(root.getRef('chapter'), isA<CRDTMapRefHandler>());
    });

    test('child leaves the kind behind, so it outlives the call', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(doc, 'root').child('done', doneSpec);

      expect(
        doc.resolveHandler(const HandlerRef('other', doneType)),
        isNotNull,
      );
    });

    test('two handlers of one kind are not a conflict', () {
      // Each constructor mints its own spec from the tag, so comparing them by
      // identity would make this ordinary shape throw in debug.
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
        CRDTRegisterHandler.spec<bool>(doneType),
        CRDTRegisterHandler.spec<bool>(doneType),
      );
      expect(
        CRDTRegisterHandler.spec<bool>(doneType),
        isNot(CRDTRegisterHandler.spec<bool>('other')),
      );
    });
  });

  group('the value types behave as values', () {
    test('equal descriptions land on one another in a set', () {
      // They are compared and hashed wherever a kind is looked up, so `==` and
      // `hashCode` have to agree.
      final one = CRDTRegisterHandler.spec<bool>(doneType);
      final same = CRDTRegisterHandler.spec<bool>(doneType);

      expect({one, same}, hasLength(1));
      expect({one.formats, same.formats}, hasLength(1));
      expect(
        {one.formats.blobVersions, same.formats.blobVersions},
        hasLength(1),
      );
    });

    test('a different tag is a different kind', () {
      final done = CRDTRegisterHandler.spec<bool>(doneType);
      final other = CRDTRegisterHandler.spec<bool>('other');

      expect({done, other}, hasLength(2));
    });
  });

  group('a declaration is checked against the decoders', () {
    test('a handler whose formats disagree with its decoders is caught', () {
      // A wrong `formats` tells a peer this build reads a kind it cannot
      // decode, so the peer sends it. A handler of your own is the one stating
      // them, so this is where the risk lives.
      //
      // Built by hand on purpose: registering is what every handler does, and
      // it is the only point a handler that never went through a spec reaches.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(
        () => _WrongFormats<int>(doc, 'x'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a spec that builds another kind is caught', () {
      // A handler built under a tag nobody addresses is a child a peer never
      // finds. Only [HandlerSpec.create] can see this: the handler itself is
      // self-consistent.
      final doc = CRDTDocument(peerId: PeerId.generate());
      final mislabelled = HandlerSpec<CRDTFugueTextHandler>(
        'not-the-tag-it-carries',
        CRDTFugueTextHandler.new,
        formats: CRDTFugueTextHandler.spec.formats,
      );

      expect(
        () => mislabelled.create(doc, 'x'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('BaseCRDTDocument.register', () {
    test('declares a kind this peer never opens', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);

      expect(doc.registeredHandlers, isEmpty);
      expect(doc.resolveHandler(const HandlerRef('x', doneType)), isNotNull);
    });

    test('reads the formats off a handler instead of restating them', () {
      // Derived, so they cannot drift from the decoders that dispatch.
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..register(PNCounterHandler.spec('PNCounterHandler'));

      // The tag comes off the probe too, so it is the one the handler carries.
      expect(
        doc.describeBuildCapabilities()['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
    });

    test('the probe does not land on this document', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..register(doneSpec);

      expect(doc.registeredHandlers, isEmpty);
      expect(doc.exportChanges(), isEmpty);
      expect(doc.version, isEmpty);
    });

    test('refuses a disposed document', () {
      final doc = CRDTDocument(peerId: PeerId.generate())..dispose();

      expect(
        () => doc.register(doneSpec),
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

const _wrongSpec = HandlerSpec<_WrongFormats<int>>(
  'WrongFormats<T>',
  _WrongFormats<int>.new,
  formats: HandlerFormats(
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
