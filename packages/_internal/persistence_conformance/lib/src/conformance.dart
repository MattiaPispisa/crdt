import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/src/fixtures.dart';
import 'package:test/test.dart';

/// Checks a [CRDTDocumentStorage] implementation against the contract every
/// adapter has to keep.
///
/// Call it from the adapter's own test file and add only what is specific to
/// that backend — schema creation, type ids, closing a database:
///
/// ```dart
/// void main() {
///   runDocumentStorageConformanceTests(
///     name: 'CRDTHive',
///     open: (documentId) => CRDTHive.openStorageForDocument(documentId),
///   );
/// }
/// ```
///
/// [open] must return a storage for the given document id, reading back what a
/// previous call for the same id stored. Pass `durable: false` for a store
/// that cannot do that — an in-memory one — and the group that reopens is
/// skipped.
///
/// [dispose] is called after each test with the storages it opened, for a
/// backend that has to close a handle.
///
/// Pass `atomicTransactions: true` for a backend whose
/// [CRDTDocumentStorage.transaction] really rolls back. The default is the
/// contract's own default, which just runs the body: a backend without
/// transactions is still conformant, so the rollback case only runs when the
/// adapter claims it.
///
/// Pass `synchronous: true` for a backend whose reads answer without
/// suspending, and the suite checks that they really do and that
/// [CRDTDocumentPersistence.openSync] restores through them. An asynchronous
/// backend is still conformant, so the group only runs when the adapter
/// claims it.
///
/// [openPeerIds] gives the [CRDTPeerIdStorage] of a document id, and adds the
/// group that checks stored identity. Leave it out on an adapter that keeps
/// no identity.
void runDocumentStorageConformanceTests({
  required String name,
  required Future<CRDTDocumentStorage> Function(String documentId) open,
  bool durable = true,
  bool atomicTransactions = false,
  bool synchronous = false,
  Future<CRDTPeerIdStorage> Function(String documentId)? openPeerIds,
  Future<void> Function(CRDTDocumentStorage storage)? dispose,
}) {
  group('$name conformance', () {
    var counter = 0;
    final opened = <CRDTDocumentStorage>[];
    late String documentId;
    late CRDTDocumentStorage storage;
    late ConformanceFixtures fixtures;

    Future<CRDTDocumentStorage> openStorage(String id) async {
      final result = await open(id);
      opened.add(result);
      return result;
    }

    setUp(() async {
      // A fresh id per test: a backend that shares one database between
      // documents must not carry the previous test's rows into this one.
      final stamp = DateTime.now().microsecondsSinceEpoch;
      documentId = 'conformance-${counter++}-$stamp';
      storage = await openStorage(documentId);
      fixtures = ConformanceFixtures(documentId);
    });

    tearDown(() async {
      for (final each in opened) {
        await dispose?.call(each);
      }
      opened.clear();
    });

    group('copying', () {
      test('copyDocument carries a whole document to another storage',
          () async {
        final changes = fixtures.everyHandler();
        final snapshot = fixtures.snapshot();
        await storage.changes.saveChanges(changes);
        await storage.snapshots.saveSnapshot(snapshot);

        final other = await openStorage('$documentId-copy');
        await storage.copyTo(other);

        expect(await other.changes.count, changes.length);
        expect((await other.snapshots.getSnapshots()).single.id, snapshot.id);

        final rebuilt = await other.readDocument();
        ConformanceFixtures.expectEveryHandler(
          rebuilt,
          (actual, expected) => expect(actual, expected),
        );
      });

      test('copying twice leaves what copying once left', () async {
        await storage.changes.saveChanges(fixtures.changes(3));

        final other = await openStorage('$documentId-copy');
        await storage.copyTo(other);
        await storage.copyTo(other);

        expect(await other.changes.count, 3);
      });
    });

    group('changes', () {
      test('an empty storage reads back nothing', () async {
        expect(await storage.changes.getChanges(), isEmpty);
        expect(await storage.changes.count, 0);
      });

      test('round-trips a change, payload bytes included', () async {
        final change = fixtures.changes(1).single;

        await storage.changes.saveChange(change);

        final stored = await storage.changes.getChanges();
        expect(stored, hasLength(1));
        expect(stored.single.id, change.id);
        expect(stored.single.toBytes(), change.toBytes());
      });

      test('round-trips a change carrying a nested value', () async {
        final change = fixtures.complexChange();

        await storage.changes.saveChange(change);

        final stored = await storage.changes.getChanges();
        expect(stored.single.toBytes(), change.toBytes());
      });

      test('saveChanges stores the whole batch', () async {
        final changes = fixtures.changes(5);

        await storage.changes.saveChanges(changes);

        expect(await storage.changes.count, 5);
        expect(
          (await storage.changes.getChanges()).map((c) => c.id).toSet(),
          changes.map((c) => c.id).toSet(),
        );
      });

      test('saving the same change twice keeps one copy', () async {
        final change = fixtures.changes(1).single;

        await storage.changes.saveChange(change);
        await storage.changes.saveChange(change);

        expect(await storage.changes.count, 1);
      });

      test('deleteChange answers true, then false', () async {
        final change = fixtures.changes(1).single;
        await storage.changes.saveChange(change);

        expect(await storage.changes.deleteChange(change), isTrue);
        expect(await storage.changes.deleteChange(change), isFalse);
        expect(await storage.changes.count, 0);
      });

      test('deleteChanges counts only what was there', () async {
        final changes = fixtures.changes(3);
        await storage.changes.saveChanges(changes.take(2).toList());

        expect(await storage.changes.deleteChanges(changes), 2);
        expect(await storage.changes.count, 0);
      });

      test('a change named twice in one batch counts once', () async {
        final changes = fixtures.changes(1);
        await storage.changes.saveChanges(changes);

        expect(
          await storage.changes.deleteChanges([...changes, ...changes]),
          1,
        );
        expect(await storage.changes.count, 0);
      });

      test('the empty batch is not an error', () async {
        await storage.changes.saveChanges([]);
        expect(await storage.changes.deleteChanges([]), 0);
        expect(await storage.changes.count, 0);
      });

      test('clear empties the storage', () async {
        await storage.changes.saveChanges(fixtures.changes(3));

        await storage.changes.clear();

        expect(await storage.changes.getChanges(), isEmpty);
      });
    });

    group('snapshots', () {
      test('an empty storage reads back nothing', () async {
        expect(await storage.snapshots.getSnapshots(), isEmpty);
        expect(await storage.snapshots.count, 0);
      });

      test('round-trips a snapshot, state bytes included', () async {
        fixtures.changes(3);
        final snapshot = fixtures.snapshot();

        await storage.snapshots.saveSnapshot(snapshot);

        final stored = await storage.snapshots.getSnapshots();
        expect(stored, hasLength(1));
        expect(stored.single.toBytes(), snapshot.toBytes());
      });

      test('getSnapshot finds it by id, and misses cleanly', () async {
        fixtures.changes(1);
        final snapshot = fixtures.snapshot();
        await storage.snapshots.saveSnapshot(snapshot);

        expect(
          (await storage.snapshots.getSnapshot(snapshot.id))?.id,
          snapshot.id,
        );
        expect(await storage.snapshots.getSnapshot('missing'), isNull);
      });

      test('containsSnapshot reflects presence', () async {
        fixtures.changes(1);
        final snapshot = fixtures.snapshot();

        expect(await storage.snapshots.containsSnapshot(snapshot.id), isFalse);
        await storage.snapshots.saveSnapshot(snapshot);
        expect(await storage.snapshots.containsSnapshot(snapshot.id), isTrue);
      });

      test('saveSnapshots stores the whole batch', () async {
        fixtures.changes(1);
        final first = fixtures.snapshot();
        fixtures.changes(1);
        final second = fixtures.snapshot();

        await storage.snapshots.saveSnapshots([first, second]);

        expect(await storage.snapshots.count, 2);
      });

      test('deleteSnapshot answers true, then false', () async {
        fixtures.changes(1);
        final snapshot = fixtures.snapshot();
        await storage.snapshots.saveSnapshot(snapshot);

        expect(await storage.snapshots.deleteSnapshot(snapshot.id), isTrue);
        expect(await storage.snapshots.deleteSnapshot(snapshot.id), isFalse);
      });

      test('deleteSnapshots counts only what was there', () async {
        fixtures.changes(1);
        final snapshot = fixtures.snapshot();
        await storage.snapshots.saveSnapshot(snapshot);

        expect(
          await storage.snapshots.deleteSnapshots([snapshot.id, 'missing']),
          1,
        );
      });

      test('an id named twice in one batch counts once', () async {
        final snapshot = fixtures.snapshot();
        await storage.snapshots.saveSnapshot(snapshot);

        expect(
          await storage.snapshots.deleteSnapshots([snapshot.id, snapshot.id]),
          1,
        );
        expect(await storage.snapshots.count, 0);
      });

      test('the empty batch is not an error', () async {
        await storage.snapshots.saveSnapshots([]);
        expect(await storage.snapshots.deleteSnapshots([]), 0);
      });

      test('clear empties the storage', () async {
        fixtures.changes(1);
        await storage.snapshots.saveSnapshot(fixtures.snapshot());

        await storage.snapshots.clear();

        expect(await storage.snapshots.getSnapshots(), isEmpty);
      });
    });

    group('every handler', () {
      test('round-trips through the change log', () async {
        final changes = fixtures.everyHandler();

        await storage.changes.saveChanges(changes);

        final reloaded = CRDTDocument(documentId: documentId)
          ..importChanges(await storage.changes.getChanges());
        ConformanceFixtures.expectEveryHandler(
          reloaded,
          (actual, expected) => expect(actual, equals(expected)),
        );
      });

      test('round-trips through a snapshot', () async {
        fixtures.everyHandler();

        await storage.snapshots.saveSnapshot(fixtures.snapshot());

        final stored = (await storage.snapshots.getSnapshots()).single;
        final reloaded = CRDTDocument(documentId: documentId)
          ..importSnapshot(stored);
        ConformanceFixtures.expectEveryHandler(
          reloaded,
          (actual, expected) => expect(actual, equals(expected)),
        );
      });
    });

    group('version vector', () {
      test('newerThan keeps only what the vector has not seen', () async {
        final before = fixtures.changes(2);
        final seen = fixtures.document.getVersionVector();
        final after = fixtures.changes(3);
        await storage.changes.saveChanges([...before, ...after]);

        final read = await storage.changes.getChanges(newerThan: seen);

        expect(
          read.map((c) => c.id.toString()),
          unorderedEquals(after.map((c) => c.id.toString())),
        );
      });

      test('upTo keeps only what the vector has seen', () async {
        final before = fixtures.changes(2);
        final seen = fixtures.document.getVersionVector();
        final after = fixtures.changes(3);
        await storage.changes.saveChanges([...before, ...after]);

        final read = await storage.changes.getChanges(upTo: seen);

        expect(
          read.map((c) => c.id.toString()),
          unorderedEquals(before.map((c) => c.id.toString())),
        );
      });

      test('the two together keep what sits between them', () async {
        final before = fixtures.changes(2);
        final start = fixtures.document.getVersionVector();
        final middle = fixtures.changes(3);
        final end = fixtures.document.getVersionVector();
        final after = fixtures.changes(2);
        await storage.changes.saveChanges([...before, ...middle, ...after]);

        final read = await storage.changes.getChanges(
          newerThan: start,
          upTo: end,
        );

        expect(
          read.map((c) => c.id.toString()),
          unorderedEquals(middle.map((c) => c.id.toString())),
        );
      });

      test('an empty vector has seen nothing', () async {
        final changes = fixtures.changes(3);
        await storage.changes.saveChanges(changes);

        expect(
          await storage.changes.getChanges(newerThan: VersionVector({})),
          hasLength(3),
        );
        expect(
          await storage.changes.getChanges(upTo: VersionVector({})),
          isEmpty,
        );
      });

      test('a peer the vector never heard of is newer than it', () async {
        final mine = fixtures.changes(2);
        final other = ConformanceFixtures('$documentId-stranger');
        final theirs = other.changes(2);
        await storage.changes.saveChanges([...mine, ...theirs]);

        final read = await storage.changes.getChanges(
          newerThan: fixtures.document.getVersionVector(),
        );

        expect(
          read.map((c) => c.id.toString()),
          unorderedEquals(theirs.map((c) => c.id.toString())),
        );
      });
    });

    test('documentId is the same on both halves', () {
      expect(storage.documentId, documentId);
      expect(storage.changes.documentId, documentId);
      expect(storage.snapshots.documentId, documentId);
    });

    test('two documents do not see each other', () async {
      final otherId = '$documentId-other';
      final other = await openStorage(otherId);
      final otherFixtures = ConformanceFixtures(otherId);

      await storage.changes.saveChanges(fixtures.changes(2));
      await other.changes.saveChanges(otherFixtures.changes(3));

      expect(await storage.changes.count, 2);
      expect(await other.changes.count, 3);

      await storage.changes.clear();

      expect(await other.changes.count, 3);
    });

    group('transactions', () {
      test('runs the body and hands back what it returned', () async {
        final changes = fixtures.changes(2);

        final written = await storage.transaction(() async {
          await storage.changes.saveChanges(changes);
          return storage.changes.count;
        });

        expect(written, 2);
        expect(await storage.changes.count, 2);
      });

      test('a body that throws throws through', () async {
        await expectLater(
          storage.transaction(() async => throw StateError('no')),
          throwsA(isA<StateError>()),
        );
      });

      if (atomicTransactions) {
        test('a body that throws leaves nothing behind', () async {
          await storage.changes.saveChanges(fixtures.changes(1));

          await expectLater(
            storage.transaction(() async {
              await storage.changes.saveChanges(fixtures.changes(2));
              throw StateError('no');
            }),
            throwsA(isA<StateError>()),
          );

          expect(
            await storage.changes.count,
            1,
            reason: 'only what was there before the transaction',
          );
        });
      }
    });

    if (openPeerIds != null) {
      group('peer id', () {
        test('reads back null before anything wrote one', () async {
          final peers = await openPeerIds(documentId);

          expect(await peers.getPeerId(), isNull);
        });

        test('round-trips the stored id', () async {
          final peers = await openPeerIds(documentId);
          final id = PeerId.generate();

          await peers.savePeerId(id);

          expect(await peers.getPeerId(), id);
        });

        test('loadOrCreate mints one and then keeps it', () async {
          final peers = await openPeerIds(documentId);

          final first = await peers.loadOrCreate();
          final second = await peers.loadOrCreate();

          expect(second, first);
          expect(await peers.getPeerId(), first);
        });

        test('two documents do not share an identity', () async {
          final mine = await openPeerIds(documentId);
          final other = await openPeerIds('$documentId-other');

          expect(await other.loadOrCreate(), isNot(await mine.loadOrCreate()));
        });
      });
    }

    if (synchronous) {
      group('synchronous', () {
        test('reads answer without suspending', () {
          expect(storage.changes.getChanges(), isNot(isA<Future<dynamic>>()));
          expect(storage.changes.count, isNot(isA<Future<dynamic>>()));
          expect(
            storage.snapshots.getSnapshots(),
            isNot(isA<Future<dynamic>>()),
          );
          expect(storage.snapshots.count, isNot(isA<Future<dynamic>>()));
        });

        test('openSync restores the document before it returns', () async {
          final changes = fixtures.changes(3);
          await storage.changes.saveChanges(changes);

          final document = CRDTDocument(documentId: documentId);
          final persistence = CRDTDocumentPersistence.openSync(
            document,
            storage,
          );

          expect(
            document.exportChanges().map((c) => c.id.toString()),
            unorderedEquals(changes.map((c) => c.id.toString())),
          );

          await persistence.dispose();
        });
      });
    }

    test('close is not an error the second time', () async {
      await storage.close();
      await storage.close();
    });

    if (durable) {
      test('what was stored is still there after closing', () async {
        final changes = fixtures.changes(2);
        await storage.changes.saveChanges(changes);
        await storage.close();

        final reopened = await openStorage(documentId);

        expect(
          (await reopened.changes.getChanges()).map((c) => c.toBytes()),
          unorderedEquals(changes.map((c) => c.toBytes())),
        );
      });

      test('what was stored is still there after reopening', () async {
        final changes = fixtures.changes(3);
        fixtures.changes(1);
        final snapshot = fixtures.snapshot();
        await storage.changes.saveChanges(changes);
        await storage.snapshots.saveSnapshot(snapshot);
        for (final each in opened) {
          await dispose?.call(each);
        }
        opened.clear();

        final reopened = await openStorage(documentId);

        expect(
          (await reopened.changes.getChanges()).map((c) => c.toBytes()),
          unorderedEquals(changes.map((c) => c.toBytes())),
        );
        expect(
          (await reopened.snapshots.getSnapshots()).single.toBytes(),
          snapshot.toBytes(),
        );
      });
    }
  });
}


/// Checks a [CRDTStorageBackend] implementation against the contract every
/// adapter has to keep.
///
/// The other half of [runDocumentStorageConformanceTests]: that one checks
/// what holds one document, this one checks what holds the documents.
///
/// ```dart
/// void main() {
///   runStorageBackendConformanceTests(
///     name: 'CRDTSqlite',
///     open: () => CRDTSqlite.memory(),
///   );
/// }
/// ```
///
/// [open] returns a fresh, empty backend. Pass [reopen] as well for a backend
/// that can be closed and opened again on the same data — it is what checks
/// that [CRDTStorageBackend.documentIds] survives a restart, and it is skipped
/// without it.
void runStorageBackendConformanceTests({
  required String name,
  required FutureOr<CRDTStorageBackend> Function() open,
  FutureOr<CRDTStorageBackend> Function(CRDTStorageBackend previous)? reopen,
}) {
  group('$name backend conformance', () {
    late CRDTStorageBackend backend;
    late ConformanceFixtures fixtures;

    setUp(() async {
      backend = await open();
      fixtures = ConformanceFixtures('doc-a');
    });

    tearDown(() async {
      await backend.close();
    });

    /// Stores one change under [documentId], so the document exists.
    Future<void> write(String documentId) async {
      final storage = await backend.storageForDocument(documentId);
      await storage.changes.saveChanges(fixtures.changes(1));
    }

    test('an empty backend holds no documents', () async {
      expect(await backend.documentIds, isEmpty);
    });

    test('a document is listed once something of it is stored', () async {
      await write('doc-a');

      expect(await backend.documentIds, {'doc-a'});
    });

    test('a document whose only trace is its identity is listed too',
        () async {
      final peers = await backend.peerIdStorageForDocument('doc-a');
      await peers.savePeerId(PeerId.generate());

      expect(
        await backend.documentIds,
        {'doc-a'},
        reason: 'a document that was opened and never written to still exists',
      );
    });

    test('asking twice gives a storage that reads the first one back',
        () async {
      await write('doc-a');

      final again = await backend.storageForDocument('doc-a');

      expect(await again.changes.count, 1);
    });

    test('the storage of a document is scoped to that document', () async {
      await write('doc-a');

      final other = await backend.storageForDocument('doc-b');

      expect(await other.changes.count, 0);
      expect(other.documentId, 'doc-b');
    });

    test('every document keeps its own identity', () async {
      final a = await backend.peerIdStorageForDocument('doc-a');
      final b = await backend.peerIdStorageForDocument('doc-b');
      final id = PeerId.generate();
      await a.savePeerId(id);

      expect(await a.getPeerId(), id);
      expect(await b.getPeerId(), isNull);
    });

    test('deleteDocument removes the changes, the snapshots and the identity',
        () async {
      final storage = await backend.storageForDocument('doc-a');
      await storage.changes.saveChanges(fixtures.changes(2));
      await storage.snapshots.saveSnapshot(fixtures.snapshot());
      final peers = await backend.peerIdStorageForDocument('doc-a');
      await peers.savePeerId(PeerId.generate());

      await backend.deleteDocument('doc-a');

      expect(await backend.documentIds, isEmpty);
      final after = await backend.storageForDocument('doc-a');
      expect(await after.changes.count, 0);
      expect(await after.snapshots.count, 0);
      expect(
        await (await backend.peerIdStorageForDocument('doc-a')).getPeerId(),
        isNull,
      );
    });

    test('deleteDocument leaves the other documents alone', () async {
      await write('doc-a');
      await write('doc-b');

      await backend.deleteDocument('doc-a');

      expect(await backend.documentIds, {'doc-b'});
      expect(
        await (await backend.storageForDocument('doc-b')).changes.count,
        1,
      );
    });

    test('deleting a document that is not there is not an error', () async {
      await backend.deleteDocument('never-existed');
    });

    test('close is not an error the second time', () async {
      await backend.close();
      await backend.close();
    });

    test('a document moves to another backend whole', () async {
      final storage = await backend.storageForDocument('doc-a');
      await storage.changes.saveChanges(fixtures.everyHandler());
      final peers = await backend.peerIdStorageForDocument('doc-a');
      final identity = PeerId.generate();
      await peers.savePeerId(identity);

      final other = await open();
      addTearDown(() async => other.close());
      await backend.copyDocumentTo(other, 'doc-a');

      expect(await other.documentIds, contains('doc-a'));
      expect(
        await (await other.peerIdStorageForDocument('doc-a')).getPeerId(),
        identity,
      );
      ConformanceFixtures.expectEveryHandler(
        await other.readDocument('doc-a'),
        (actual, expected) => expect(actual, expected),
      );
    });

    if (reopen != null) {
      test('the documents are still listed after a reopen', () async {
        await write('doc-a');
        await write('doc-b');
        await backend.close();

        backend = await reopen(backend);

        expect(await backend.documentIds, {'doc-a', 'doc-b'});
      });
    }
  });
}
