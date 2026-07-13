import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Storage utility for managing [Snapshot] objects in a SQLite [sq-Database].
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTSqliteSnapshotStorage {
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

  /// The unique identifier for the document these snapshots belong to.
  final String documentId;

  /// Saves a [Snapshot] to the storage.
  ///
  /// If a snapshot with the same id already exists it is overwritten.
  void saveSnapshot(Snapshot snapshot) {
    database.execute(
      'INSERT OR REPLACE INTO $snapshotsTable '
      '(document_id, snapshot_id, bytes) VALUES (?, ?, ?)',
      [documentId, snapshot.id, snapshot.toBytes()],
    );
  }

  /// Saves multiple [Snapshot] objects to the storage.
  ///
  /// This method is more efficient than calling [saveSnapshot] multiple times
  /// as it reuses a single prepared statement.
  void saveSnapshots(List<Snapshot> snapshots) {
    if (snapshots.isEmpty) {
      return;
    }
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
  }

  /// Retrieves a [Snapshot] by its id.
  ///
  /// Returns the [Snapshot] if found, or null otherwise.
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

  /// Retrieves all [Snapshot] objects from the storage for this document.
  List<Snapshot> getSnapshots() {
    final result = database.select(
      'SELECT bytes FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result
        .map((row) => Snapshot.fromBytes(row['bytes'] as Uint8List))
        .toList();
  }

  /// Deletes a [Snapshot] by its id.
  ///
  /// Returns true if the snapshot was found and deleted, false otherwise.
  bool deleteSnapshot(String id) {
    if (!containsSnapshot(id)) {
      return false;
    }
    database.execute(
      'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
      [documentId, id],
    );
    return true;
  }

  /// Deletes multiple [Snapshot] objects by their ids.
  ///
  /// Returns the number of snapshots that were actually deleted.
  int deleteSnapshots(List<String> ids) {
    if (ids.isEmpty) {
      return 0;
    }
    var deleted = 0;
    final statement = database.prepare(
      'DELETE FROM $snapshotsTable WHERE document_id = ? AND snapshot_id = ?',
    );
    try {
      for (final id in ids) {
        if (containsSnapshot(id)) {
          statement.execute([documentId, id]);
          deleted += 1;
        }
      }
    } finally {
      statement.close();
    }
    return deleted;
  }

  /// Clears all [Snapshot] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  void clear() {
    database.execute(
      'DELETE FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
  }

  /// Checks if a [Snapshot] with the given [id] exists for this document.
  bool containsSnapshot(String id) {
    return database.select(
      'SELECT 1 FROM $snapshotsTable '
      'WHERE document_id = ? AND snapshot_id = ? LIMIT 1',
      [documentId, id],
    ).isNotEmpty;
  }

  /// Returns the number of [Snapshot] objects for this document in the storage.
  int get count {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $snapshotsTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }

  /// Returns true if the storage is empty for this document.
  bool get isEmpty => count == 0;

  /// Returns true if the storage is not empty for this document.
  bool get isNotEmpty => count > 0;
}
