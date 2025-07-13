import 'package:crdt_lf/crdt_lf.dart';

import 'database.dart';
import 'storage/change_storage.dart';
import 'storage/snapshot_storage.dart';

/// Container class for both change and snapshot storage for a document.
class CRDTDocumentStorage {
  /// Creates a new [CRDTDocumentStorage] instance.
  const CRDTDocumentStorage({
    required this.changes,
    required this.snapshots,
  });

  /// The change storage for the document.
  final CRDTChangeStorage changes;

  /// The snapshot storage for the document.
  final CRDTSnapshotStorage snapshots;
}

/// Main utility class for managing CRDT persistence with Drift.
///
/// This class provides methods to initialize and manage Drift databases
/// for CRDT objects and to create document-scoped storage utilities.
///
/// Databases can be managed manually using Drift's native methods or by
/// leveraging the convenience utilities provided by [CRDTDrift]:
///
/// - [CRDTDrift.openChangeStorageForDocument]
/// - [CRDTDrift.openSnapshotStorageForDocument]
/// - [CRDTDrift.openStorageForDocument]
class CRDTDrift {
  /// Private constructor to prevent instantiation.
  CRDTDrift._();

  /// Global database instance map to manage multiple databases.
  static final Map<String, CRDTDatabase> _databases = {};

  /// Gets or creates a database instance for the given path.
  static CRDTDatabase _getDatabase(String? path) {
    final key = path ?? 'default';
    return _databases.putIfAbsent(key, () => CRDTDatabase(path));
  }

  /// Creates a [CRDTChangeStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Change]s.
  ///
  /// Each document can be isolated by using different database paths
  /// or by organizing within the same database using document IDs.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [databasePath] is the path where the database file will be stored.
  /// If not provided, uses a default database.
  static Future<CRDTChangeStorage> openChangeStorageForDocument(
    String documentId, {
    String? databasePath,
  }) async {
    final database = _getDatabase(databasePath);
    return CRDTChangeStorage(database, documentId);
  }

  /// Creates a [CRDTSnapshotStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Snapshot]s.
  ///
  /// Each document can be isolated by using different database paths
  /// or by organizing within the same database using document IDs.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [databasePath] is the path where the database file will be stored.
  /// If not provided, uses a default database.
  static Future<CRDTSnapshotStorage> openSnapshotStorageForDocument(
    String documentId, {
    String? databasePath,
  }) async {
    final database = _getDatabase(databasePath);
    return CRDTSnapshotStorage(database, documentId);
  }

  /// Creates both change and snapshot storage for a specific document.
  ///
  /// Returns a [CRDTDocumentStorage] containing both storage instances
  /// for convenience.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [databasePath] is the path where the database file will be stored.
  /// If not provided, uses a default database.
  static Future<CRDTDocumentStorage> openStorageForDocument(
    String documentId, {
    String? databasePath,
  }) async {
    final database = _getDatabase(databasePath);
    return CRDTDocumentStorage(
      changes: CRDTChangeStorage(database, documentId),
      snapshots: CRDTSnapshotStorage(database, documentId),
    );
  }

  /// Closes a specific database.
  ///
  /// [databasePath] is the path of the database to close.
  /// If not provided, closes the default database.
  static Future<void> closeDatabase([String? databasePath]) async {
    final key = databasePath ?? 'default';
    final database = _databases.remove(key);
    if (database != null) {
      await database.close();
    }
  }

  /// Closes all open databases.
  ///
  /// This method closes all databases that were opened by [CRDTDrift].
  /// It's useful for cleanup when shutting down the application.
  static Future<void> closeAllDatabases() async {
    final futures = _databases.values.map((db) => db.close());
    await Future.wait(futures);
    _databases.clear();
  }

  /// Gets an existing database instance.
  ///
  /// Returns null if no database exists for the given path.
  /// [databasePath] is the path of the database to retrieve.
  /// If not provided, returns the default database.
  static CRDTDatabase? getDatabase([String? databasePath]) {
    final key = databasePath ?? 'default';
    return _databases[key];
  }

  /// Creates a database instance with in-memory storage for testing.
  ///
  /// [key] is used to identify this test database instance.
  static CRDTDatabase createTestDatabase([String key = 'test']) {
    final database = CRDTDatabase.memory();
    _databases[key] = database;
    return database;
  }

  /// Deletes all data for a specific document from a database.
  ///
  /// This removes all changes and snapshots associated with the document.
  /// Use with caution as this operation cannot be undone.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [databasePath] is the path of the database. If not provided, uses the default database.
  static Future<void> deleteDocumentData(
    String documentId, {
    String? databasePath,
  }) async {
    final database = _getDatabase(databasePath);
    
    await Future.wait([
      (database.delete(database.changes)
            ..where((tbl) => tbl.documentId.equals(documentId)))
          .go(),
      (database.delete(database.snapshots)
            ..where((tbl) => tbl.documentId.equals(documentId)))
          .go(),
    ]);
  }
} 