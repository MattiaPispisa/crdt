@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
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
}
