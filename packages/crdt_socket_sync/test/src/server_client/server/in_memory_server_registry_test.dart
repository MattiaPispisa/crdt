import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server_client/server/in_memory_server_registry.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryCRDTServerRegistry', () {
    late InMemoryCRDTServerRegistry registry;

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
    });

    test('adds, gets, checks and counts documents', () async {
      expect(await registry.hasDocument('doc'), isFalse);
      expect(await registry.getDocument('doc'), isNull);
      expect(await registry.documentCount, 0);

      await registry.addDocument('doc');

      expect(await registry.hasDocument('doc'), isTrue);
      expect(await registry.getDocument('doc'), isA<CRDTDocument>());
      expect(await registry.documentCount, 1);
      expect(await registry.documentIds, {'doc'});
    });

    test('removes documents and their snapshots', () async {
      await registry.addDocument('doc');
      await registry.createSnapshot('doc');
      expect(await registry.getLatestSnapshot('doc'), isA<Snapshot>());

      await registry.removeDocument('doc');

      expect(await registry.hasDocument('doc'), isFalse);
      expect(await registry.getLatestSnapshot('doc'), isNull);
    });

    test('clear empties documents and snapshots', () async {
      await registry.addDocument('a');
      await registry.addDocument('b');
      await registry.createSnapshot('a');

      await registry.clear();

      expect(await registry.documentCount, 0);
      expect(registry.documents, isEmpty);
      expect(registry.snapshots, isEmpty);
    });

    test('createSnapshot throws for an unknown document', () {
      expect(
        () => registry.createSnapshot('missing'),
        throwsArgumentError,
      );
    });

    test('applyChange throws for an unknown document', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'list').insert(0, 'a');
      final change = doc.exportChanges().first;

      expect(
        () => registry.applyChange('missing', change),
        throwsArgumentError,
      );
    });

    test('applyChange applies a ready change and dedups duplicates', () async {
      await registry.addDocument('doc');

      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(authorDoc, 'list').insert(0, 'a');
      final change = authorDoc.exportChanges().first;

      expect(await registry.applyChange('doc', change), isTrue);
      // Re-applying the same change is a no-op duplicate.
      expect(await registry.applyChange('doc', change), isFalse);
    });

    test(
      'applyChange rethrows CausallyNotReadyException for missing deps',
      () async {
        await registry.addDocument('doc');

        // Two causally dependent changes; apply only the second.
        final authorDoc = CRDTDocument(peerId: PeerId.generate());
        CRDTListHandler<String>(authorDoc, 'list')
          ..insert(0, 'a')
          ..insert(1, 'b');
        final orphan = authorDoc.exportChanges()[1];

        // Regression: this used to be swallowed and returned as `false`,
        // which killed the server's out-of-sync recovery path.
        await expectLater(
          () => registry.applyChange('doc', orphan),
          throwsA(isA<CausallyNotReadyException>()),
        );
      },
    );

    test(
      'a change carrying an unknown operation kind is not an out-of-sync one',
      () async {
        await registry.addDocument('doc');
        final document = (await registry.getDocument('doc'))!;
        final text = CRDTFugueTextHandler(document, 'text');

        final author = PeerId.generate();
        final change = Change.fromPayloadBytes(
          id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
          deps: {},
          author: author,
          payloadBytes: OperationEnvelopeCodec.encode(
            handlerType: text.handlerType,
            handlerId: text.id,
            kind: 99,
            // Stamped, so the kind is what the read trips over: the handler
            // is stamped and an envelope without one fails on another guard.
            stamp: OperationStamp(
              hlc: HybridLogicalClock(l: 100, c: 1),
              peerId: author,
            ),
            body: Uint8List(0),
          ),
        );

        // Applying is zero-decode, so the change lands. What matters is that it
        // is not reported as a causality gap: the server answers that with a
        // resync, and resyncing cannot teach an old peer a newer operation.
        expect(await registry.applyChange('doc', change), isTrue);

        // The disagreement shows up on the read instead, where the client can
        // turn it into "this peer needs an upgrade".
        expect(
          () => text.value,
          throwsA(isA<UnknownOperationKindException>()),
        );
      },
    );
  });
}
