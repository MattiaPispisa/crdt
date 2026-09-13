import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/capabilities/formats_of.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

/// Every built-in handler, with the formats its class declares.
///
/// The declaration and `operationDecoders` are written a few lines apart in the
/// same file, and nothing makes them agree. This is where they are compared.
///
/// Each class keeps its declaration private, so it is read back through the
/// spec — the only public way to it, and the one a peer actually receives. That
/// matters most for the three ref containers: their declaration is a **copy**
/// of the handler they extend, and this table is what keeps the copy honest.
final _handlers = <String, (HandlerFormats, Handler<dynamic> Function(
    CRDTDocument doc))>{
  'CRDTTextHandler': (
    CRDTTextHandler.spec.formats,
    (doc) => CRDTTextHandler(doc, 'text'),
  ),
  'CRDTFugueTextHandler': (
    CRDTFugueTextHandler.spec.formats,
    (doc) => CRDTFugueTextHandler(doc, 'fugue_text'),
  ),
  'CRDTFugueListHandler': (
    CRDTFugueListHandler.spec<String>('x').formats,
    (doc) => CRDTFugueListHandler<String>(doc, 'fugue_list'),
  ),
  'CRDTFugueMovableListHandler': (
    CRDTFugueMovableListHandler.spec<String>('x').formats,
    (doc) => CRDTFugueMovableListHandler<String>(doc, 'movable'),
  ),
  'CRDTListHandler': (
    CRDTListHandler.spec<String>('x').formats,
    (doc) => CRDTListHandler<String>(doc, 'list'),
  ),
  'CRDTMapHandler': (
    CRDTMapHandler.spec<int>('x').formats,
    (doc) => CRDTMapHandler<int>(doc, 'map'),
  ),
  'CRDTORSetHandler': (
    CRDTORSetHandler.spec<String>('x').formats,
    (doc) => CRDTORSetHandler<String>(doc, 'or_set'),
  ),
  'CRDTORMapHandler': (
    CRDTORMapHandler.spec<String, int>('x').formats,
    (doc) => CRDTORMapHandler<String, int>(doc, 'or_map'),
  ),
  'CRDTRegisterHandler': (
    CRDTRegisterHandler.spec<int>('x').formats,
    (doc) => CRDTRegisterHandler<int>(doc, 'register'),
  ),
  'CRDTMapRefHandler': (
    CRDTMapRefHandler.spec.formats,
    (doc) => CRDTMapRefHandler(doc, 'map_ref'),
  ),
  'CRDTListRefHandler': (
    CRDTListRefHandler.spec.formats,
    (doc) => CRDTListRefHandler(doc, 'list_ref'),
  ),
  'CRDTMovableListRefHandler': (
    CRDTMovableListRefHandler.spec.formats,
    (doc) => CRDTMovableListRefHandler(doc, 'movable_ref'),
  ),
};


void main() {
  group('a handler declares what it reads', () {
    for (final entry in _handlers.entries) {
      test('${entry.key} declares the decoders it dispatches on', () {
        final (declared, build) = entry.value;
        final handler = build(CRDTDocument(peerId: PeerId.generate()));

        // The invariant the const table rests on. A decoder added without
        // adding its kind here would make this build under-declare, and the
        // peer that sends that kind would be let in and then fail on read.
        expect(handler.operationDecoders.keys.toSet(), declared.operationKinds);

        // The blob range is derived from the declaration, so this pins the
        // derivation rather than a second hand-written value.
        expect(formatsOf(handler).blobVersions, declared.blobVersions);
      });
    }
  });

  group('the types this package ships', () {
    final builtIn = <HandlerSpec<Handler<dynamic>>>[
      CRDTTextHandler.spec,
      CRDTFugueTextHandler.spec,
      CRDTMapRefHandler.spec,
      CRDTListRefHandler.spec,
      CRDTMovableListRefHandler.spec,
    ];

    test('resolve with nothing registered', () {
      // They need no registration: the classes are in this build, so a ref to
      // one can always be rebuilt. That is what a peer receiving a nested child
      // of a type it never opened depends on.
      final doc = CRDTDocument(peerId: PeerId.generate());

      for (final spec in builtIn) {
        expect(
          doc.resolveHandler(HandlerRef('id-${spec.type}', spec.type)),
          isNotNull,
          reason: spec.type,
        );
      }
    });

    test('are not a claim about what this peer reads', () {
      // Being able to rebuild a type is not the same as being set up for it.
      // An empty description says the peer has not spoken yet, and a relay that
      // only forwards bytes should not claim five types it never uses.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(doc.describeBuildCapabilities().handlerTypes, isEmpty);
    });
  });

  group('CRDTDocument.describeBuildCapabilities', () {
    test('covers a handler that is already open', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter');

      expect(
        doc.describeBuildCapabilities()['PNCounterHandler'],
        HandlerFormats(
          operationKinds: counter.operationDecoders.keys.toSet(),
          blobVersions: BlobVersionRange(
            counter.minReadableSnapshotBlobVersion,
            counter.snapshotBlobVersion,
          ),
        ),
      );
    });

    test('covers a registered type, and only a registered one', () {
      // A build that could read a type says so before the app opens one:
      // reading the handler registry alone would report nothing here. Silence
      // still means nobody set the type up, not that this build cannot read it.
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..register(
          HandlerSpec.factory(
            'PNCounterHandler',
            PNCounterHandler.new,
            formats: const HandlerFormats(
              operationKinds: {PNCounterHandler.incrementKind},
              blobVersions: BlobVersionRange.single(1),
            ),
          ),
        );

      expect(doc.registeredHandlers, isEmpty);
      final capabilities = doc.describeBuildCapabilities();
      expect(
        capabilities['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
      expect(capabilities['NeverSetUp'], isNull);
    });

    test('builds nothing: no factory runs and the document does not move', () {
      // Formats are declared, never discovered. A factory that would blow up
      // is never called, so asking the question cannot fail or leave a trace.
      var calls = 0;
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..register(
          HandlerSpec.factory(
            'Broken',
            (d, id) {
              calls += 1;
              throw StateError('nope');
            },
            formats: const HandlerFormats(operationKinds: {0}),
          ),
        )
        ..describeBuildCapabilities()
        ..describeBuildCapabilities();

      expect(calls, 0);
      expect(doc.registeredHandlers, isEmpty);
      expect(doc.exportChanges(), isEmpty);
      expect(doc.version, isEmpty);
    });

    test('an open handler is keyed by the tag it carries on the wire', () {
      // The envelope carries the handler's own tag, so that is the one that
      // has to match the other peer — not the id it was opened under.
      final doc = CRDTDocument(peerId: PeerId.generate());
      PNCounterHandler(
        doc,
        'some-id',
        spec: HandlerSpec<PNCounterHandler>(
          'declared-as-this',
          (d, id, spec) => PNCounterHandler(d, id, spec: spec),
          formats: const HandlerFormats(
            operationKinds: {PNCounterHandler.incrementKind},
            blobVersions: BlobVersionRange.single(1),
          ),
        ),
      );

      expect(
        doc.describeBuildCapabilities()['declared-as-this'],
        isNotNull,
      );
    });

    test('states the blob range each type reads', () {
      // What makes a blob version checkable at all: it travels next to the
      // kinds, keyed by handler type, because a snapshot blob on its own
      // cannot be tied back to a type.
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'text');

      expect(
        doc.describeBuildCapabilities()['CRDTFugueTextHandler']?.blobVersions,
        BlobVersionRange(
          text.minReadableSnapshotBlobVersion,
          text.snapshotBlobVersion,
        ),
      );
    });

    test('is read-only: the maps it hands out cannot be edited', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      PNCounterHandler(doc, 'counter');
      final capabilities = doc.describeBuildCapabilities();

      expect(capabilities.byHandlerType.clear, throwsUnsupportedError);
      expect(
        () => capabilities['PNCounterHandler']!.operationKinds.add(9),
        throwsUnsupportedError,
      );
    });
  });
}
