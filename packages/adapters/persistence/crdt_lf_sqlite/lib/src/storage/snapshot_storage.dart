import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Stores [Snapshot] objects in a SQLite [sq.Database].
///
/// All rows are scoped to a single document via the [documentId] column, so
/// several documents can share the same database.
///
/// sqlite3 is synchronous, so every method here answers without ever
/// suspending. They return futures to keep the [CRDTSnapshotStorage] contract,
/// which the asynchronous backends need.
class CRDTSqliteSnapshotStorage implements CRDTSnapshotStorage {
  /// Creates a new [CRDTSqliteSnapshotStorage] instance.
  ///
  /// [database] is the SQLite database used to store [Snapshot] objects; its
  /// schema must already have been created (see [createSchemaSql]).
  ///
  /// [documentId] is the unique identifier for the document these snapshots
  /// belong to.
  CRDTSqliteSnapshotStorage(this.database, this.documentId);

  /// The SQLite database used for storing [Snapshot] objects.
  final sq.Database database;

  @override
  final String documentId;

  @override
  Future<void> saveSnapshot(Snapshot snapshot) async {
    database.execute(
      'INSERT OR REPLACE INTO $snapshotsTable '
      '(document_id, snapshot_id, bytes) VALUES (?, ?, ?)',
      [documentId, snapshot.id, snapshot.toBytes()],
    );
  }

  /// {@macro crdt_lf_sqlite_batch}
  @override
  Future<void> saveSnapshots(List<Snapshot> snapshots) async {
    if (snapshots.isEmpty) {
      return;
    }
    final statement = database.prepare(
      'INSERT OR REPLACE INTO $snapshotsTable '
      '(document_id, snapshot_id, bytes) VALUES (?, ?, ?)',
    );
    try {
      runInTransaction(database, () {
        for (final snapshot in snapshots) {
          statement.execute([documentId, snapshot.id, snapshot.toBytes()]);
        }
      });
    } finally {
      statement.close();
    }
  }

  @override
  Future<Snapshot?> getSnapshot(String id) async {
    final result = database.select(
      'SELECT bytes FROM $snapshotsTable '
      'WHERE document_id = ? AND snapshot_id = ? LIMIT 1',
      [documentId, id],
    );
    if (result.isEmpty) {
      return null;
    }
    return Snapshot.fromBytes(result.first['bytes'] as Uint8List);
  }

  @override
  Future<List<Snapshot>> getSnapshots() async {
    final result = database.select(
      'SELECT bytes FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result
        .map((row) => Snapshot.fromBytes(row['bytes'] as Uint8List))
        .toList();
  }

  @override
  Future<bool> deleteSnapshot(String id) async {
    if (!_contains(id)) {
      return false;
    }
    database.execute(
      'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
      [documentId, id],
    );
    return true;
  }

  /// {@macro crdt_lf_sqlite_batch}
  @override
  Future<int> deleteSnapshots(List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    var deleted = 0;
    final statement = database.prepare(
      'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
    );
    try {
      runInTransaction(database, () {
        for (final id in ids) {
          if (_contains(id)) {
            statement.execute([documentId, id]);
            deleted += 1;
          }
        }
      });
    } finally {
      statement.close();
    }
    return deleted;
  }

  @override
  Future<void> clear() async {
    database.execute(
      'DELETE FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
  }

  @override
  Future<bool> containsSnapshot(String id) async => _contains(id);

  bool _contains(String id) {
    return database.select(
      'SELECT 1 FROM $snapshotsTable '
      'WHERE document_id = ? AND snapshot_id = ? LIMIT 1',
      [documentId, id],
    ).isNotEmpty;
  }

  @override
  Future<int> get count async {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }
}
