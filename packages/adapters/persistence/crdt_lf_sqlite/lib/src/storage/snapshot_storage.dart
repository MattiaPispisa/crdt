import 'dart:async';
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
/// suspending, and says so in its return type.
///
/// The batch methods are the exception: they keep the [FutureOr] because
/// [runInTransaction] defers them when another asynchronous transaction holds
/// the connection.
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
  void saveSnapshot(Snapshot snapshot) {
    database.execute(
      'INSERT OR REPLACE INTO $snapshotsTable '
      '(document_id, snapshot_id, bytes) VALUES (?, ?, ?)',
      [documentId, snapshot.id, snapshot.toBytes()],
    );
  }

  /// {@macro crdt_lf_sqlite_batch}
  ///
  /// {@macro crdt_lf_sqlite_batch_defer}
  @override
  FutureOr<void> saveSnapshots(List<Snapshot> snapshots) {
    if (snapshots.isEmpty) {
      return null;
    }
    return runInTransaction(database, () {
      final statement = database.prepare(
        'INSERT OR REPLACE INTO $snapshotsTable '
        '(document_id, snapshot_id, bytes) VALUES (?, ?, ?)',
      );
      try {
        for (final snapshot in snapshots) {
          statement.execute([documentId, snapshot.id, snapshot.toBytes()]);
        }
      } finally {
        statement.close();
      }
    });
  }

  @override
  Snapshot? getSnapshot(String id) {
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
  List<Snapshot> getSnapshots() {
    final result = database.select(
      'SELECT bytes FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result
        .map((row) => Snapshot.fromBytes(row['bytes'] as Uint8List))
        .toList();
  }

  /// Deletes the snapshot with the given [id], and says whether it was there.
  ///
  /// The check and the delete go in one transaction: two statements without
  /// one would let another write on this connection land between them.
  @override
  FutureOr<bool> deleteSnapshot(String id) {
    return runInTransaction(database, () {
      if (!_contains(id)) {
        return false;
      }
      database.execute(
        'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
        [documentId, id],
      );
      return true;
    });
  }

  /// {@macro crdt_lf_sqlite_batch}
  ///
  /// {@macro crdt_lf_sqlite_batch_defer}
  @override
  FutureOr<int> deleteSnapshots(List<String> ids) {
    if (ids.isEmpty) {
      return 0;
    }
    return runInTransaction(database, () {
      var deleted = 0;
      final statement = database.prepare(
        'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
      );
      try {
        for (final id in ids) {
          if (_contains(id)) {
            statement.execute([documentId, id]);
            deleted += 1;
          }
        }
      } finally {
        statement.close();
      }
      return deleted;
    });
  }

  @override
  void clear() {
    database.execute(
      'DELETE FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
  }

  @override
  bool containsSnapshot(String id) => _contains(id);

  bool _contains(String id) {
    return database.select(
      'SELECT 1 FROM $snapshotsTable '
      'WHERE document_id = ? AND snapshot_id = ? LIMIT 1',
      [documentId, id],
    ).isNotEmpty;
  }

  @override
  int get count {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }
}
