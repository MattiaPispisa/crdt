import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:crdt_lf_sqlite/src/storage/change_storage.dart';
import 'package:crdt_lf_sqlite/src/storage/document_storage.dart';
import 'package:crdt_lf_sqlite/src/storage/peer_id_storage.dart';
import 'package:crdt_lf_sqlite/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Main utility class for persisting CRDT objects in a SQLite database.
///
/// A single [CRDTSqlite] instance wraps one SQLite [sq.Database] holding two
/// tables (`changes` and `snapshots`). Data for different documents lives in
/// the same tables and is isolated through an indexed `document_id` column, so
/// you can persist any number of documents in a single database file.
///
/// ```dart
/// final storage = CRDTSqlite.open('app.db');
/// final changes = storage.changeStorageForDocument('doc-1');
/// ...
/// storage.close();
/// ```
class CRDTSqlite {
  CRDTSqlite._(this.database);

  /// Opens (creating it if necessary) the SQLite database at [path] and
  /// ensures the CRDT schema exists.
  factory CRDTSqlite.open(String path) {
    final database = sq.sqlite3.open(path);
    _createSchema(database);
    return CRDTSqlite._(database);
  }

  /// Opens an in-memory SQLite database and ensures the CRDT schema exists.
  ///
  /// Useful for tests and ephemeral usage.
  factory CRDTSqlite.memory() {
    final database = sq.sqlite3.openInMemory();
    _createSchema(database);
    return CRDTSqlite._(database);
  }

  /// Wraps an existing [database], ensuring the CRDT schema exists.
  ///
  /// Use this to share a database connection you already manage elsewhere.
  factory CRDTSqlite.fromDatabase(sq.Database database) {
    _createSchema(database);
    return CRDTSqlite._(database);
  }

  /// The underlying SQLite database.
  final sq.Database database;

  static void _createSchema(sq.Database database) {
    database.execute(createSchemaSql);
  }

  /// Creates a [CRDTSqliteChangeStorage] scoped to [documentId].
  CRDTSqliteChangeStorage changeStorageForDocument(String documentId) {
    return CRDTSqliteChangeStorage(database, documentId);
  }

  /// Creates a [CRDTSqliteSnapshotStorage] scoped to [documentId].
  CRDTSqliteSnapshotStorage snapshotStorageForDocument(String documentId) {
    return CRDTSqliteSnapshotStorage(database, documentId);
  }

  /// Creates a [CRDTSqlitePeerIdStorage] scoped to [documentId].
  ///
  /// Read it before building the document, so the document keeps the identity
  /// it wrote under last time:
  ///
  /// ```dart
  /// final peerId = database.peerIdStorageForDocument('doc-1').loadOrCreate();
  /// final document = CRDTDocument(documentId: 'doc-1', peerId: peerId);
  /// ```
  CRDTSqlitePeerIdStorage peerIdStorageForDocument(String documentId) {
    return CRDTSqlitePeerIdStorage(database, documentId);
  }

  /// Creates both change and snapshot storage for [documentId], bundled in a
  /// [CRDTSqliteDocumentStorage].
  CRDTSqliteDocumentStorage storageForDocument(String documentId) {
    return CRDTSqliteDocumentStorage(
      database: database,
      changes: changeStorageForDocument(documentId),
      snapshots: snapshotStorageForDocument(documentId),
    );
  }

  /// Deletes the changes, snapshots and stored identity of [documentId].
  ///
  /// Use with caution as this operation cannot be undone. The three deletes
  /// go in one transaction, so the document never comes back as a half of
  /// itself.
  void deleteDocumentData(String documentId) {
    runInTransaction(database, () {
      database
        ..execute(
          'DELETE FROM $changesTable WHERE document_id = ?',
          [documentId],
        )
        ..execute(
          'DELETE FROM $snapshotsTable WHERE document_id = ?',
          [documentId],
        )
        ..execute(
          'DELETE FROM $peersTable WHERE document_id = ?',
          [documentId],
        );
    });
  }

  /// Closes the underlying database and releases its resources.
  void close() {
    database.close();
  }
}
