import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

void main() {
  group('CRDTDocument.describeBuildCapabilities', () {
    test('covers a handler that is already open', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter');

      expect(
        doc.describeBuildCapabilities()['PNCounterHandler'],
        counter.decodableKinds,
      );
    });

    test('covers a type that no handler has opened yet', () {
      // The whole point: a build that *could* read a type says so, without
      // waiting for the app to open one. Reading the handler registry alone
      // would report nothing here.
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..registerFactory('PNCounterHandler', PNCounterHandler.new);

      expect(doc.registeredHandlers, isEmpty);
      expect(
        doc.describeBuildCapabilities()['PNCounterHandler'],
        {PNCounterHandler.incrementKind},
      );
    });

    test('leaves the document it is called on untouched', () {
      // The invariant that makes probing acceptable: a factory is run on a
      // document of its own, so nothing is registered here as a side effect of
      // asking a question.
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..registerFactory('PNCounterHandler', PNCounterHandler.new);

      expect(doc.describeBuildCapabilities(), isNotEmpty);
      expect(doc.registeredHandlers, isEmpty);
      expect(doc.exportChanges(), isEmpty);
      expect(doc.version, isEmpty);
    });

    test('a factory that throws does not hide the other types', () {
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..registerFactory('Broken', (d, id) => throw StateError('nope'))
        ..registerFactory('PNCounterHandler', PNCounterHandler.new);

      final capabilities = doc.describeBuildCapabilities();

      expect(capabilities['Broken'], isNull);
      expect(capabilities['PNCounterHandler'], isNotNull);
    });

    test('keys by the type tag the handler carries on the wire', () {
      // A factory registered under one key whose handler declares another: the
      // envelope carries the handler's own tag, so that is the one that has to
      // match the other peer.
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..registerFactory(
          'registered-under-this',
          (d, id) => PNCounterHandler(d, id, handlerType: 'declared-as-this'),
        );

      final capabilities = doc.describeBuildCapabilities();

      expect(capabilities['declared-as-this'], isNotNull);
      expect(capabilities['registered-under-this'], isNull);
    });

    test('is read-only: the maps it hands out cannot be edited', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      PNCounterHandler(doc, 'counter');
      final capabilities = doc.describeBuildCapabilities();

      expect(capabilities.clear, throwsUnsupportedError);
      expect(
        () => capabilities['PNCounterHandler']!.add(9),
        throwsUnsupportedError,
      );
    });
  });

  group('CRDTDocument.registeredFactoryTypes', () {
    test('lists the types a factory was registered for', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      expect(doc.registeredFactoryTypes, isEmpty);

      doc.registerFactory('A', PNCounterHandler.new);

      expect(doc.registeredFactoryTypes, ['A']);
    });
  });
}
