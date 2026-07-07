import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart';
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
  });
}
