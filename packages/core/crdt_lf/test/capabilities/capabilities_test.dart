import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

/// Every built-in handler, built once so its declaration can be compared with
/// the decoders it dispatches on.
///
/// The two are written a few lines apart in the same file and nothing makes
/// them agree. This is where they are compared — and it is the only way to a
/// declaration now, since each class keeps it private and answers it through
/// [Handler.spec].
///
/// It matters most for the three ref containers: their declaration is a
/// **copy** of the handler they extend, and this table keeps the copy honest.
final _handlers = <(
  HandlerSpec<Handler<dynamic>>,
  Handler<dynamic> Function(CRDTDocument doc)
)>[
  (CRDTTextHandler.spec, (doc) => CRDTTextHandler(doc, 'text')),
  (CRDTFugueTextHandler.spec, (doc) => CRDTFugueTextHandler(doc, 'fugue_text')),
  (
    CRDTFugueListHandler.spec<String>('fl'),
    (doc) => CRDTFugueListHandler<String>(doc, 'fugue_list', handlerType: 'fl'),
  ),
  (
    CRDTFugueMovableListHandler.spec<String>('ml'),
    (doc) => CRDTFugueMovableListHandler<String>(
          doc,
          'movable',
          handlerType: 'ml',
        ),
  ),
  (
    CRDTListHandler.spec<String>('l'),
    (doc) => CRDTListHandler<String>(doc, 'list', handlerType: 'l'),
  ),
  (
    CRDTMapHandler.spec<int>('m'),
    (doc) => CRDTMapHandler<int>(doc, 'map', handlerType: 'm'),
  ),
  (
    CRDTORSetHandler.spec<String>('os'),
    (doc) => CRDTORSetHandler<String>(doc, 'or_set', handlerType: 'os'),
  ),
  (
    CRDTORMapHandler.spec<String, int>('om'),
    (doc) => CRDTORMapHandler<String, int>(doc, 'or_map', handlerType: 'om'),
  ),
  (
    CRDTRegisterHandler.spec<int>('r'),
    (doc) => CRDTRegisterHandler<int>(doc, 'register', handlerType: 'r'),
  ),
  (CRDTMapRefHandler.spec, (doc) => CRDTMapRefHandler(doc, 'map_ref')),
  (CRDTListRefHandler.spec, (doc) => CRDTListRefHandler(doc, 'list_ref')),
  (
    CRDTMovableListRefHandler.spec,
    (doc) => CRDTMovableListRefHandler(doc, 'movable_ref'),
  ),
];

void main() {
  group('a handler declares what it reads', () {
    for (final (declared, build) in _handlers) {
      final handler = build(CRDTDocument(peerId: PeerId.generate()));
      test('${handler.handlerType} declares the decoders it dispatches on', () {
        // A decoder added without adding its kind to the declaration would make
        // this build under-declare, and the peer that sends that kind would be
        // let in and then fail on read.
        expect(
          handler.operationDecoders.keys.toSet(),
          declared.formats.operationKinds,
        );

        // The blob range is derived from the same constant, so this pins the
        // derivation rather than a second hand-written value.
        expect(
          HandlerFormats.of(handler).blobVersions,
          declared.formats.blobVersions,
        );
      });
    }
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
        ..register(PNCounterHandler.spec('PNCounterHandler'));

      expect(doc.registeredHandlers, isEmpty);
      final capabilities = doc.describeBuildCapabilities();
      expect(
        capabilities['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
      expect(capabilities['NeverSetUp'], isNull);
    });

    test('declaring a kind builds nothing and moves nothing', () {
      // A spec says what a kind is without making one. Nothing is constructed,
      // here or anywhere: the builder it holds runs only when a reference has
      // to be resolved.
      var built = 0;
      final counted = HandlerSpec<PNCounterHandler>(
        'counter',
        (doc, id) {
          built += 1;
          return PNCounterHandler(doc, id, handlerType: 'counter');
        },
        formats: const HandlerFormats(
          operationKinds: {PNCounterHandler.incrementKind},
          blobVersions: BlobVersionRange.single(1),
        ),
      );

      final doc = CRDTDocument(peerId: PeerId.generate())
        ..register(counted)
        ..describeBuildCapabilities()
        ..describeBuildCapabilities();

      expect(built, 0);
      expect(doc.registeredHandlers, isEmpty);
      expect(doc.exportChanges(), isEmpty);
      expect(doc.version, isEmpty);
    });

    test('an open handler is keyed by the tag it carries on the wire', () {
      // The envelope carries the handler's own tag, so that is the one that
      // has to match the other peer — not the id it was opened under.
      final doc = CRDTDocument(peerId: PeerId.generate());
      PNCounterHandler(doc, 'some-id', handlerType: 'declared-as-this');

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
