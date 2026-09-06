@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crdt_sqlite_test');
    dbPath = '${tempDir.path}/crdt.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // One database handle per storage, closed by the suite, so the group that
  // reopens really reads the file back.
  final handles = <CRDTDocumentStorage, CRDTSqlite>{};

  runStorageBackendConformanceTests(
    name: 'CRDTSqlite',
    open: () => CRDTSqlite.open(dbPath),
    reopen: (_) => CRDTSqlite.open(dbPath),
  );

  runDocumentStorageConformanceTests(
    name: 'CRDTSqlite',
    atomicTransactions: true,
    synchronous: true,
    openPeerIds: (documentId) async =>
        CRDTSqlite.open(dbPath).peerIdStorageForDocument(documentId),
    open: (documentId) async {
      final database = CRDTSqlite.open(dbPath);
      final storage = database.storageForDocument(documentId);
      handles[storage] = database;
      return storage;
    },
    dispose: (storage) async => handles.remove(storage)?.close(),
  );

  group('CRDTSqlite', () {
    late CRDTSqlite storage;

    setUp(() {
      storage = CRDTSqlite.open(dbPath);
    });

    tearDown(() {
      storage.close();
    });

    Change makeChange(int l, int c) {
      final id = OperationId(
        PeerId.generate(),
        HybridLogicalClock(l: l, c: c),
      );
      return Change.fromPayloadBytes(
        id: id,
        deps: const {},
        author: id.peerId,
        payloadBytes: Uint8List.fromList(utf8.encode('$l.$c')),
      );
    }

    test('storageForDocument returns the sqlite storages', () {
      final documentStorage = storage.storageForDocument('doc');

      expect(documentStorage.documentId, 'doc');
      expect(documentStorage.changes, isA<CRDTSqliteChangeStorage>());
      expect(documentStorage.snapshots, isA<CRDTSqliteSnapshotStorage>());
    });

    test('runInTransaction rolls back partial work on error', () async {
      final changes = storage.changeStorageForDocument('doc-rollback');

      expect(
        () => runInTransaction(storage.database, () {
          // This insert happens inside the open transaction...
          changes.saveChange(makeChange(1, 1));
          // ...but the failure must roll it back.
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      expect(changes.count, isZero, reason: 'partial work rolled back');
    });

    // Two documents sharing one connection write at the same time. Each
    // CRDTDocumentPersistence has its own write chain, so nothing serialises
    // them, and an asynchronous body suspends inside the open transaction.
    // A savepoint rolls back every write made after it, the other document's
    // included, so the two must not overlap.
    test('a failing transaction leaves a concurrent one intact', () async {
      final a = storage.changeStorageForDocument('doc-a');
      final aWrote = Completer<void>();

      final futureA = runInTransaction(storage.database, () async {
        await Future<void>.delayed(Duration.zero);
        a.saveChange(makeChange(1, 1));
        aWrote.complete();
        return 'a';
      });

      final futureB = runInTransaction(storage.database, () async {
        await aWrote.future;
        throw StateError('boom');
      });

      await futureA;
      await expectLater(futureB, throwsA(isA<StateError>()));

      expect(
        a.count,
        1,
        reason: "B's rollback must not undo A's write",
      );
    });

    // A batch method opens a savepoint of its own, and drops the result. If a
    // nested call queued behind the transaction it is already inside, the work
    // would be deferred past that transaction and lost with it.
    test('a storage call nested after an await still lands', () async {
      final changes = storage.changeStorageForDocument('doc-nested');

      final result = runInTransaction(storage.database, () async {
        await Future<void>.delayed(Duration.zero);
        changes.saveChanges([makeChange(1, 1)]);
        return 'done';
      });
      await (result as Future<String>);

      expect(changes.count, 1);
    });

    // The bug this pins: a batch prepared its statement outside
    // `runInTransaction` and dropped the returned future. While another
    // asynchronous transaction holds the connection the body is deferred, so
    // the statement was already closed when it ran, and the caller was told
    // the batch had landed while nothing had been written.
    test('a batch deferred behind another transaction still lands', () async {
      final other = storage.changeStorageForDocument('doc-other');
      final batch = storage.changeStorageForDocument('doc-batch');
      final holding = Completer<void>();
      final release = Completer<void>();

      final held = runInTransaction(storage.database, () async {
        holding.complete();
        await release.future;
        other.saveChange(makeChange(1, 1));
      });

      await holding.future;
      final written = batch.saveChanges([makeChange(2, 1), makeChange(2, 2)]);
      expect(
        written,
        isA<Future<void>>(),
        reason: 'a deferred batch must say so instead of reporting success',
      );

      release.complete();
      await held;
      await written;

      expect(batch.count, 2);
      expect(other.count, 1);
    });

    test('a deferred delete batch reports what it really deleted', () async {
      final batch = storage.changeStorageForDocument('doc-deferred-delete');
      final changes = [makeChange(3, 1), makeChange(3, 2)];
      await batch.saveChanges(changes);

      final holding = Completer<void>();
      final release = Completer<void>();
      final held = runInTransaction(storage.database, () async {
        holding.complete();
        await release.future;
      });

      await holding.future;
      final deleting = batch.deleteChanges(changes);
      release.complete();
      await held;

      expect(await deleting, 2);
      expect(batch.count, isZero);
    });

    test('a synchronous body never suspends', () {
      final result = runInTransaction(storage.database, () => 'done');

      expect(result, isNot(isA<Future<dynamic>>()));
      expect(result, 'done');
    });

    test('memory() works without a file', () async {
      final memory = CRDTSqlite.memory();
      final changes = memory.changeStorageForDocument('doc')
        ..saveChange(makeChange(1, 1));

      expect(changes.count, 1);
      memory.close();
    });

    test('fromDatabase wraps an existing connection', () async {
      final memory = CRDTSqlite.memory();
      final wrapped = CRDTSqlite.fromDatabase(memory.database);

      final changes = wrapped.changeStorageForDocument('doc')
        ..saveChange(makeChange(1, 1));

      expect(changes.count, 1);
      memory.close();
    });

    test('deleteDocument removes only the target document', () async {
      final a = storage.storageForDocument('doc-a');
      final b = storage.storageForDocument('doc-b');
      final id = OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));

      a.changes.saveChange(makeChange(1, 1));
      a.snapshots.saveSnapshot(
        Snapshot(
          id: 's-del',
          versionVector: VersionVector({id.peerId: id.hlc}),
          data: {
            'd': Uint8List.fromList([1]),
          },
        ),
      );
      b.changes.saveChange(makeChange(2, 1));

      storage.deleteDocument('doc-a');

      expect(a.changes.count, 0);
      expect(a.snapshots.count, 0);
      expect(b.changes.count, 1, reason: 'doc-b must be untouched');
    });
  });

  group('schema upgrade', () {
    /// Writes a database in the shape version 1 left behind, holding
    /// [changes].
    void writeSchemaOne(List<Change> changes) {
      final database = sq.sqlite3.open(dbPath);
      try {
        database.execute('''
CREATE TABLE $changesTable (
  document_id TEXT NOT NULL,
  change_id   TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, change_id)
);
''');
        for (final change in changes) {
          database.execute(
            'INSERT INTO $changesTable VALUES (?, ?, ?)',
            ['doc', change.id.toString(), change.toBytes()],
          );
        }
      } finally {
        database.close();
      }
    }

    test('a database written by version 1 keeps its rows and can be filtered',
        () async {
      // Version 1 had no author and no clock column, and no `user_version`
      // either. The upgrade adds the columns and fills them from the bytes
      // that are already on disk, or the bounds would answer on zeros.
      final author = PeerId.generate();
      Change atClock(int l) => Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: l, c: 1)),
            deps: const {},
            author: author,
            payloadBytes: Uint8List.fromList(utf8.encode('$l')),
          );
      final older = atClock(1);
      final newer = atClock(2);
      writeSchemaOne([older, newer]);

      final upgraded = CRDTSqlite.open(dbPath);
      final changes = upgraded.changeStorageForDocument('doc');

      expect(
        changes.count,
        2,
        reason: 'the upgrade only adds, it does not drop rows',
      );
      expect(
        changes
            .getChanges(newerThan: VersionVector({author: older.hlc}))
            .map((change) => change.id.toString()),
        [newer.id.toString()],
        reason: 'the columns were filled from the bytes already on disk',
      );

      upgraded.close();
    });

    test('the tables version 1 never had are created', () async {
      writeSchemaOne([]);

      final upgraded = CRDTSqlite.open(dbPath);
      final peerId = PeerId.generate();
      final peers = upgraded.peerIdStorageForDocument('doc')
        ..savePeerId(peerId);

      expect(peers.getPeerId(), peerId);
      upgraded.close();
    });

    test('a change whose bytes this build cannot read still migrates',
        () async {
      // The split reads `change_id`, not the blob. A row this build could not
      // decode would once have stopped the upgrade; now it moves across and
      // fails later, when someone actually asks for it.
      final id = OperationId(PeerId.generate(), HybridLogicalClock(l: 7, c: 0));
      sq.sqlite3.open(dbPath)
        ..execute('''
CREATE TABLE $changesTable (
  document_id TEXT NOT NULL,
  change_id   TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, change_id)
);
''')
        ..execute(
          'INSERT INTO $changesTable VALUES (?, ?, ?)',
          [
            'doc',
            id.toString(),
            Uint8List.fromList([1]),
          ],
        )
        ..close();

      final upgraded = CRDTSqlite.open(dbPath);

      expect(upgraded.changeStorageForDocument('doc').count, 1);
      expect(
        () => upgraded
            .changeStorageForDocument('doc')
            .getChanges(upTo: VersionVector({id.peerId: id.hlc})),
        // Reading it is what fails, and only for whoever asks.
        throwsA(isA<FormatException>()),
      );

      upgraded.close();
    });

    test(
        'an upgrade that cannot read a change id leaves the database as it '
        'was', () async {
      // A name the split cannot parse stops the upgrade. Half the rows moved
      // and half left behind is worse than refusing to open.
      sq.sqlite3.open(dbPath)
        ..execute('''
CREATE TABLE $changesTable (
  document_id TEXT NOT NULL,
  change_id   TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, change_id)
);
''')
        ..execute(
          "INSERT INTO $changesTable VALUES ('doc', 'not-an-id', x'01')",
        )
        ..close();

      expect(() => CRDTSqlite.open(dbPath), throwsA(isA<FormatException>()));

      final after = sq.sqlite3.open(dbPath);
      final columns = after
          .select('PRAGMA table_info($changesTable)')
          .map((row) => row['name'])
          .toSet();
      after.close();

      expect(
        columns,
        contains('change_id'),
        reason: 'the table went back to the shape it had',
      );
    });

    test('opening twice does not upgrade twice', () async {
      final author = PeerId.generate();
      final change = Change.fromPayloadBytes(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        deps: const {},
        author: author,
        payloadBytes: Uint8List.fromList(utf8.encode('a')),
      );
      writeSchemaOne([change]);

      CRDTSqlite.open(dbPath).close();
      final again = CRDTSqlite.open(dbPath);

      expect(
        again
            .changeStorageForDocument('doc')
            .getChanges(newerThan: VersionVector({author: change.hlc})),
        isEmpty,
      );
      again.close();
    });
  });
}
