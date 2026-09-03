@TestOn('vm')
library;

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

  runDocumentStorageConformanceTests(
    name: 'CRDTSqlite',
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

      expect(await changes.count, isZero, reason: 'partial work rolled back');
    });

    test('memory() works without a file', () async {
      final memory = CRDTSqlite.memory();
      final changes = memory.changeStorageForDocument('doc');

      await changes.saveChange(makeChange(1, 1));

      expect(await changes.count, 1);
      memory.close();
    });

    test('fromDatabase wraps an existing connection', () async {
      final memory = CRDTSqlite.memory();
      final wrapped = CRDTSqlite.fromDatabase(memory.database);

      final changes = wrapped.changeStorageForDocument('doc');
      await changes.saveChange(makeChange(1, 1));

      expect(await changes.count, 1);
      memory.close();
    });

    test('deleteDocumentData removes only the target document', () async {
      final a = storage.storageForDocument('doc-a');
      final b = storage.storageForDocument('doc-b');
      final id = OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));

      await a.changes.saveChange(makeChange(1, 1));
      await a.snapshots.saveSnapshot(
        Snapshot(
          id: 's-del',
          versionVector: VersionVector({id.peerId: id.hlc}),
          data: {
            'd': Uint8List.fromList([1]),
          },
        ),
      );
      await b.changes.saveChange(makeChange(2, 1));

      storage.deleteDocumentData('doc-a');

      expect(await a.changes.count, 0);
      expect(await a.snapshots.count, 0);
      expect(await b.changes.count, 1, reason: 'doc-b must be untouched');
    });
  });
}
