// ignore_for_file: missing_whitespace_between_adjacent_strings sql

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';
import 'package:drift/native.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crdt_drift_test');
    dbPath = '${tempDir.path}/crdt.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // One database for the whole test, closed by the suite: the group that
  // reopens closes it and asks again, so it really reads the file back.
  // Drift warns when the same file is opened twice at once, so never two.
  CRDTDrift? database;

  // Drift warns when the same file is opened twice at once, so the backend
  // suite gets a file of its own per test.
  runStorageBackendConformanceTests(
    name: 'CRDTDrift',
    open: () => CRDTDrift.open(File('$dbPath-backend')),
    reopen: (_) => CRDTDrift.open(File('$dbPath-backend')),
  );

  runDocumentStorageConformanceTests(
    name: 'CRDTDrift',
    atomicTransactions: true,
    // drift is asynchronous end to end, so no `synchronous: true` here.
    openPeerIds: (documentId) async => (database ??=
            CRDTDrift.open(File(dbPath)))
        .peerIdStorageForDocument(documentId),
    open: (documentId) async =>
        (database ??= CRDTDrift.open(File(dbPath))).storageForDocument(
      documentId,
    ),
    dispose: (_) async {
      await database?.close();
      database = null;
    },
  );

  group('CRDTDrift', () {
    late CRDTDrift storage;

    setUp(() {
      storage = CRDTDrift.open(File(dbPath));
    });

    tearDown(() async {
      await storage.close();
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

    test('storageForDocument returns the drift storages', () {
      final documentStorage = storage.storageForDocument('doc');

      expect(documentStorage.documentId, 'doc');
      expect(documentStorage.changes, isA<CRDTDriftChangeStorage>());
      expect(documentStorage.snapshots, isA<CRDTDriftSnapshotStorage>());
    });

    test('memory() works without a file', () async {
      final memory = CRDTDrift.memory();
      final changes = memory.changeStorageForDocument('doc');

      await changes.saveChange(makeChange(1, 1));

      expect(await changes.count, 1);
      await memory.close();
    });

    test('fromDatabase wraps an existing database', () async {
      final wrapped = CRDTDrift.fromDatabase(
        CRDTDriftDatabase(NativeDatabase.memory()),
      );
      final changes = wrapped.changeStorageForDocument('doc');

      await changes.saveChange(makeChange(1, 1));

      expect(await changes.count, 1);
      await wrapped.close();
    });

    test('a database written by schema 1 is upgraded, rows included', () async {
      // Schema 1 held changes and snapshots only, and no author or clock
      // column. A database on disk from that version has to keep its rows,
      // gain the identity table, and end up filterable by version — the
      // upgrade reads the stored bytes to fill the new columns.
      final author = PeerId.generate();
      Change atClock(int l) => Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: l, c: 1)),
            deps: const {},
            author: author,
            payloadBytes: Uint8List.fromList(utf8.encode('$l')),
          );
      final older = atClock(1);
      final newer = atClock(2);

      final onSchemaOne = CRDTDrift.fromDatabase(
        CRDTDriftDatabase(
          NativeDatabase.memory(
            setup: (db) {
              db
                ..execute(
                  'CREATE TABLE changes ('
                  'document_id TEXT NOT NULL, '
                  'change_id TEXT NOT NULL, '
                  'bytes BLOB NOT NULL, '
                  'PRIMARY KEY (document_id, change_id));',
                )
                ..execute(
                  'CREATE TABLE snapshots ('
                  'document_id TEXT NOT NULL, '
                  'snapshot_id TEXT NOT NULL, '
                  'bytes BLOB NOT NULL, '
                  'PRIMARY KEY (document_id, snapshot_id));',
                );
              for (final change in [older, newer]) {
                db.execute(
                  'INSERT INTO changes VALUES (?, ?, ?);',
                  ['doc', change.id.toString(), change.toBytes()],
                );
              }
              db.userVersion = 1;
            },
          ),
        ),
      );

      final peerId = PeerId.generate();
      final peers = onSchemaOne.peerIdStorageForDocument('doc');
      await peers.savePeerId(peerId);
      expect(await peers.getPeerId(), peerId);

      final changes = onSchemaOne.changeStorageForDocument('doc');
      expect(
        await changes.count,
        2,
        reason: 'the upgrade only adds, it does not drop rows',
      );

      final seenOlder = VersionVector({author: older.hlc});
      expect(
        (await changes.getChanges(newerThan: seenOlder))
            .map((change) => change.id.toString()),
        [newer.id.toString()],
        reason: 'the columns were filled from the bytes already on disk',
      );

      await onSchemaOne.close();
    });

    test('a delete of more changes than SQLite binds at once still works',
        () async {
      // One `IN (?, ?, ...)` per id: past SQLITE_MAX_VARIABLE_NUMBER the
      // statement is refused and nothing is deleted. A prune hands over
      // everything it removed at once, and `compactAfter` is off by default,
      // so a document that ran for a long time gets here.
      const count = 40000;
      final author = PeerId.generate();
      final many = [
        for (var i = 0; i < count; i++)
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 1, c: i)),
            deps: const {},
            author: author,
            payloadBytes: Uint8List.fromList(utf8.encode('$i')),
          ),
      ];
      final changes = storage.changeStorageForDocument('doc-many');
      await changes.saveChanges(many);
      expect(await changes.count, count);

      expect(await changes.deleteChanges(many), count);
      expect(await changes.count, 0);
    });

    test('deleteDocument removes only the target document', () async {
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

      await storage.deleteDocument('doc-a');

      expect(await a.changes.count, 0);
      expect(await a.snapshots.count, 0);
      expect(await b.changes.count, 1, reason: 'doc-b must be untouched');
    });
  });
}
