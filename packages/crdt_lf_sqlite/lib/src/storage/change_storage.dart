import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Storage utility for managing [Change] objects in a SQLite [sq.Database].
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTSqliteChangeStorage {
  /// Creates a new [CRDTSqliteChangeStorage] instance.
  ///
  /// [database] is the SQLite database used to store [Change] objects; its
  /// schema must already have been created (see [createSchemaSql]).
  ///
  /// [documentId] is the unique identifier for the document these changes
  /// belong to.
  CRDTSqliteChangeStorage(this.database, this.documentId);

  /// The SQLite database used for storing [Change] objects.
  final sq.Database database;

  /// The unique identifier for the document these changes belong to.
  final String documentId;

  /// Generates the row key for a change.
  String _changeKey(Change change) => change.id.toString();

  /// Saves a [Change] to the storage.
  ///
  /// If a change with the same id already exists it is overwritten.
  void saveChange(Change change) {
    database.execute(
      'INSERT OR REPLACE INTO $changesTable '
      '(document_id, change_id, bytes) VALUES (?, ?, ?)',
      [documentId, _changeKey(change), change.toBytes()],
    );
  }

  /// Saves multiple [Change] objects to the storage.
  ///
  /// This method is more efficient than calling [saveChange] multiple times
  /// as it reuses a single prepared statement.
  void saveChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return;
    }
    final statement = database.prepare(
      'INSERT OR REPLACE INTO $changesTable '
      '(document_id, change_id, bytes) VALUES (?, ?, ?)',
    );
    try {
      for (final change in changes) {
        statement.execute([documentId, _changeKey(change), change.toBytes()]);
      }
    } finally {
      statement.close();
    }
  }

  /// Retrieves all [Change] objects from the storage for this document.
  List<Change> getChanges() {
    final result = database.select(
      'SELECT bytes FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
    return result
        .map((row) => Change.fromBytes(row['bytes'] as Uint8List))
        .toList();
  }

  /// Deletes a [Change].
  ///
  /// Returns true if the change was found and deleted, false otherwise.
  bool deleteChange(Change change) {
    final key = _changeKey(change);
    if (!_contains(key)) {
      return false;
    }
    database.execute(
      'DELETE FROM $changesTable WHERE document_id = ? AND change_id = ?',
      [documentId, key],
    );
    return true;
  }

  /// Deletes multiple [Change] objects.
  ///
  /// Returns the number of changes that were actually deleted.
  int deleteChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return 0;
    }
    var deleted = 0;
    final statement = database.prepare(
      'DELETE FROM $changesTable WHERE document_id = ? AND change_id = ?',
    );
    try {
      for (final change in changes) {
        final key = _changeKey(change);
        if (_contains(key)) {
          statement.execute([documentId, key]);
          deleted += 1;
        }
      }
    } finally {
      statement.close();
    }
    return deleted;
  }

  /// Clears all [Change] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  void clear() {
    database.execute(
      'DELETE FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
  }

  bool _contains(String changeId) {
    return database.select(
      'SELECT 1 FROM $changesTable '
      'WHERE document_id = ? AND change_id = ? LIMIT 1',
      [documentId, changeId],
    ).isNotEmpty;
  }

  /// Returns the number of [Change] objects for this document in the storage.
  int get count {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }

  /// Returns true if the storage is empty for this document.
  bool get isEmpty => count == 0;

  /// Returns true if the storage is not empty for this document.
  bool get isNotEmpty => count > 0;
}
