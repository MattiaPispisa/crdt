import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Stores [Change] objects in a SQLite [sq.Database].
///
/// All rows are scoped to a single document via the [documentId] column, so
/// several documents can share the same database.
///
/// sqlite3 is synchronous, so every method here answers without ever
/// suspending. They return futures to keep the [CRDTChangeStorage] contract,
/// which the asynchronous backends need.
class CRDTSqliteChangeStorage implements CRDTChangeStorage {
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

  @override
  final String documentId;

  /// Generates the row key for a change.
  String _changeKey(Change change) => change.id.toString();

  @override
  Future<void> saveChange(Change change) async {
    database.execute(
      'INSERT OR REPLACE INTO $changesTable '
      '(document_id, change_id, bytes) VALUES (?, ?, ?)',
      [documentId, _changeKey(change), change.toBytes()],
    );
  }

  /// {@macro crdt_lf_sqlite_batch}
  @override
  Future<void> saveChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return;
    }
    final statement = database.prepare(
      'INSERT OR REPLACE INTO $changesTable '
      '(document_id, change_id, bytes) VALUES (?, ?, ?)',
    );
    try {
      runInTransaction(database, () {
        for (final change in changes) {
          statement.execute([documentId, _changeKey(change), change.toBytes()]);
        }
      });
    } finally {
      statement.close();
    }
  }

  @override
  Future<List<Change>> getChanges() async {
    final result = database.select(
      'SELECT bytes FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
    return result
        .map((row) => Change.fromBytes(row['bytes'] as Uint8List))
        .toList();
  }

  @override
  Future<bool> deleteChange(Change change) async {
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

  /// {@macro crdt_lf_sqlite_batch}
  @override
  Future<int> deleteChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return 0;
    }
    var deleted = 0;
    final statement = database.prepare(
      'DELETE FROM $changesTable WHERE document_id = ? AND change_id = ?',
    );
    try {
      runInTransaction(database, () {
        for (final change in changes) {
          final key = _changeKey(change);
          if (_contains(key)) {
            statement.execute([documentId, key]);
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

  @override
  Future<int> get count async {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }
}
