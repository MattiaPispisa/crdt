import 'dart:async';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Stores [Change] objects in a SQLite [sq.Database].
///
/// One row per change, keyed by `(document_id, author, hlc_l, hlc_c)`, with
/// the change itself as an opaque `Change.toBytes()` blob. Every row is
/// scoped to a single document through its `document_id`, so several
/// documents can share the same database.
///
/// sqlite3 is synchronous, so every method here answers without ever
/// suspending, and says so in its return type. The [CRDTChangeStorage]
/// contract asks only for a [FutureOr], which a plain value satisfies.
///
/// The batch methods are the exception: they keep the [FutureOr] because
/// [runInTransaction] defers them when another asynchronous transaction holds
/// the connection.
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

  static const String _insertSql = 'INSERT OR REPLACE INTO $changesTable '
      '(document_id, author, hlc_l, hlc_c, bytes) VALUES (?, ?, ?, ?, ?)';

  /// Matches one row: `document_id` plus the three columns an `OperationId`
  /// is written in.
  static const String _rowOfSql =
      'document_id = ? AND author = ? AND hlc_l = ? AND hlc_c = ?';

  /// The parameters [_rowOfSql] binds for [change].
  List<Object?> _rowOf(Change change) => [
        documentId,
        change.author.toString(),
        change.hlc.l,
        change.hlc.c,
      ];

  List<Object?> _row(Change change) => [
        ..._rowOf(change),
        change.toBytes(),
      ];

  @override
  void saveChange(Change change) {
    database.execute(_insertSql, _row(change));
  }

  /// {@macro crdt_lf_sqlite_batch}
  ///
  /// {@template crdt_lf_sqlite_batch_defer}
  /// The statement is prepared **inside** the transaction body and the result
  /// of [runInTransaction] is returned, not dropped. Both matter when another
  /// asynchronous transaction is already open on the connection: the body is
  /// deferred until that one ends, so a statement prepared out here would
  /// already be closed by the time the body runs, and a dropped future would
  /// tell the caller the batch had landed while nothing had been written.
  /// {@endtemplate}
  @override
  FutureOr<void> saveChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return null;
    }
    return runInTransaction(database, () {
      final statement = database.prepare(_insertSql);
      try {
        for (final change in changes) {
          statement.execute(_row(change));
        }
      } finally {
        statement.close();
      }
    });
  }

  /// The condition that holds for a change [vector] has already seen, and the
  /// parameters it binds.
  ///
  /// A change is seen when the vector holds an entry for its author and that
  /// entry is at least as new as the change — the same test
  /// [VersionVector.hasSeen] makes, written in SQL. A vector that names no
  /// peer has seen nothing, so it answers `0` rather than an empty condition.
  ///
  /// Four parameters per peer, and no document has a vector long enough for
  /// that to reach the limit SQLite puts on them.
  static ({String sql, List<Object?> params}) _seenBy(VersionVector vector) {
    final terms = <String>[];
    final params = <Object?>[];

    for (final entry in vector.entries) {
      terms.add('(author = ? AND (hlc_l < ? OR (hlc_l = ? AND hlc_c <= ?)))');
      final clock = entry.value;
      params.addAll([entry.key.toString(), clock.l, clock.l, clock.c]);
    }

    if (terms.isEmpty) {
      return (sql: '0', params: const <Object?>[]);
    }
    return (sql: '(${terms.join(' OR ')})', params: params);
  }

  @override
  List<Change> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) {
    // The bounds go to the database, not to `filterByVersion`: the rows that
    // fall outside are never read and never decoded. That is the whole cost
    // of asking a long history what is new.
    final where = StringBuffer('document_id = ?');
    final params = <Object?>[documentId];

    if (newerThan != null) {
      final seen = _seenBy(newerThan);
      where.write(' AND NOT ${seen.sql}');
      params.addAll(seen.params);
    }
    if (upTo != null) {
      final seen = _seenBy(upTo);
      where.write(' AND ${seen.sql}');
      params.addAll(seen.params);
    }

    final result = database.select(
      'SELECT bytes FROM $changesTable WHERE $where',
      params,
    );
    return [
      for (final row in result) Change.fromBytes(row['bytes'] as Uint8List),
    ];
  }

  /// Deletes [change], and says whether it was there.
  ///
  /// The check and the delete go in one transaction: two statements without
  /// one would let another write on this connection land between them.
  @override
  FutureOr<bool> deleteChange(Change change) {
    return runInTransaction(database, () {
      if (!_contains(change)) {
        return false;
      }
      database.execute(
        'DELETE FROM $changesTable WHERE $_rowOfSql',
        _rowOf(change),
      );
      return true;
    });
  }

  /// {@macro crdt_lf_sqlite_batch}
  ///
  /// {@macro crdt_lf_sqlite_batch_defer}
  @override
  FutureOr<int> deleteChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return 0;
    }
    return runInTransaction(database, () {
      var deleted = 0;
      final statement = database.prepare(
        'DELETE FROM $changesTable WHERE $_rowOfSql',
      );
      try {
        for (final change in changes) {
          if (_contains(change)) {
            statement.execute(_rowOf(change));
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
      'DELETE FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
  }

  bool _contains(Change change) {
    return database
        .select(
          'SELECT 1 FROM $changesTable WHERE $_rowOfSql LIMIT 1',
          _rowOf(change),
        )
        .isNotEmpty;
  }

  @override
  int get count {
    final result = database.select(
      'SELECT COUNT(*) AS c FROM $changesTable WHERE document_id = ?',
      [documentId],
    );
    return result.first['c'] as int;
  }
}
