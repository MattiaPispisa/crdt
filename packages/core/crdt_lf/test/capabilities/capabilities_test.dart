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
final _handlers = <Handler<dynamic> Function(CRDTDocument doc)>[
  (doc) => CRDTTextHandler(doc, 'text'),
  (doc) => CRDTFugueTextHandler(doc, 'fugue_text'),
  (doc) => CRDTFugueListHandler<String>(doc, 'fugue_list',
      handlerType: 'CRDTFugueListHandler<String>'),
  (doc) => CRDTFugueMovableListHandler<String>(doc, 'movable',
      handlerType: 'CRDTFugueMovableListHandler<String>'),
  (doc) => CRDTListHandler<String>(doc, 'list',
      handlerType: 'CRDTListHandler<String>'),
  (doc) => CRDTMapHandler<int>(doc, 'map', handlerType: 'CRDTMapHandler<int>'),
  (doc) => CRDTORSetHandler<String>(doc, 'or_set',
      handlerType: 'CRDTORSetHandler<String>'),
  (doc) => CRDTORMapHandler<String, int>(doc, 'or_map',
      handlerType: 'CRDTORMapHandler<String, int>'),
  (doc) => CRDTRegisterHandler<int>(doc, 'register',
      handlerType: 'CRDTRegisterHandler<int>'),
  (doc) => CRDTMapRefHandler(doc, 'map_ref'),
  (doc) => CRDTListRefHandler(doc, 'list_ref'),
  (doc) => CRDTMovableListRefHandler(doc, 'movable_ref'),
];

void main() {
  group('a handler declares what it reads', () {
    for (final build in _handlers) {
      final handler = build(CRDTDocument(peerId: PeerId.generate()));
      test('${handler.handlerType} declares the decoders it dispatches on', () {
        // A decoder added without adding its kind to the declaration would make
        // this build under-declare, and the peer that sends that kind would be
        // let in and then fail on read.
        expect(
          handler.operationDecoders.keys.toSet(),
          handler.spec.formats.operationKinds,
        );

        // The blob range is derived from the same constant, so this pins the
        // derivation rather than a second hand-written value.
        expect(
          HandlerFormats.of(handler).blobVersions,
          handler.spec.formats.blobVersions,
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
        ..register(PNCounterHandler.new);

      expect(doc.registeredHandlers, isEmpty);
      final capabilities = doc.describeBuildCapabilities();
      expect(
        capabilities['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
      expect(capabilities['NeverSetUp'], isNull);
    });

    test('asking twice builds nothing and moves nothing', () {
      // Registering reads the formats off one probe handler, on a document of
      // its own. Asking the question afterwards touches neither.
      var calls = 0;
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..register((d, id) {
          calls += 1;
          return PNCounterHandler(d, id);
        })
        ..describeBuildCapabilities()
        ..describeBuildCapabilities();

      expect(calls, 1, reason: 'the probe, and nothing after it');
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
