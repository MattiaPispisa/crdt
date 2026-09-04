import 'dart:io';

import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_drift/src/storage/change_storage.dart';
import 'package:crdt_lf_drift/src/storage/document_storage.dart';
import 'package:crdt_lf_drift/src/storage/peer_id_storage.dart';
import 'package:crdt_lf_drift/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Main utility class for persisting CRDT objects in a drift database.
///
/// A single [CRDTDrift] instance wraps one [CRDTDriftDatabase] holding two
/// tables (`changes` and `snapshots`). Data for different documents lives in
/// the same tables and is isolated through the `document_id` column, so you
/// can persist any number of documents in a single database.
///
/// It is the [CRDTStorageBackend] of this adapter: it lists the documents it
/// holds, hands out the storages of each one, and deletes one whole.
///
/// ```dart
/// final backend = CRDTDrift.open(File('app.db'));
///
/// for (final documentId in await backend.documentIds) {
///   final note = await backend.readDocument(documentId);
///   // ...show it in a list
/// }
///
/// final open = await backend.openDocument('doc-1');
///
/// await backend.close();
/// ```
///
/// drift is asynchronous end to end, so every method here returns a [Future].
/// That is what makes `CRDTDocumentPersistence.openSync` refuse this adapter.
class CRDTDrift implements CRDTStorageBackend {
  CRDTDrift._(this.database);

  /// Opens (creating it if necessary) a database backed by [file].
  factory CRDTDrift.open(File file) {
    return CRDTDrift._(CRDTDriftDatabase(NativeDatabase(file)));
  }

  /// Opens an in-memory database.
  ///
  /// Useful for tests and ephemeral usage.
  factory CRDTDrift.memory() {
    return CRDTDrift._(CRDTDriftDatabase(NativeDatabase.memory()));
  }

  /// Wraps an existing [database].
  ///
  /// Use this to share a database you already manage elsewhere, or to plug in
  /// a custom [QueryExecutor].
  factory CRDTDrift.fromDatabase(CRDTDriftDatabase database) {
    return CRDTDrift._(database);
  }

  /// The underlying drift database.
  final CRDTDriftDatabase database;

  bool _closed = false;

  @override
  Future<Set<String>> get documentIds async {
    // The three tables, so a document that has only an identity — added and
    // never written to — is listed as well.
    final rows = await database
        .customSelect(
          'SELECT document_id FROM ${database.changes.actualTableName} '
          'UNION SELECT document_id '
          'FROM ${database.snapshots.actualTableName} '
          'UNION SELECT document_id FROM ${database.peers.actualTableName}',
          readsFrom: {database.changes, database.snapshots, database.peers},
        )
        .get();
    return {for (final row in rows) row.read<String>('document_id')};
  }

  /// Creates a [CRDTDriftChangeStorage] scoped to [documentId].
  CRDTDriftChangeStorage changeStorageForDocument(String documentId) {
    return CRDTDriftChangeStorage(database, documentId);
  }

  /// Creates a [CRDTDriftSnapshotStorage] scoped to [documentId].
  CRDTDriftSnapshotStorage snapshotStorageForDocument(String documentId) {
    return CRDTDriftSnapshotStorage(database, documentId);
  }

  /// Creates a [CRDTDriftPeerIdStorage] scoped to [documentId].
  ///
  /// Read it before building the document, so the document keeps the identity
  /// it wrote under last time:
  ///
  /// ```dart
  /// final peers = database.peerIdStorageForDocument('doc-1');
  /// final document = CRDTDocument(
  ///   documentId: 'doc-1',
  ///   peerId: await peers.loadOrCreate(),
  /// );
  /// ```
  @override
  CRDTDriftPeerIdStorage peerIdStorageForDocument(String documentId) {
    return CRDTDriftPeerIdStorage(database, documentId);
  }

  /// Creates both change and snapshot storage for [documentId], bundled in a
  /// [CRDTDriftDocumentStorage].
  @override
  CRDTDriftDocumentStorage storageForDocument(String documentId) {
    return CRDTDriftDocumentStorage(
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
  @override
  Future<void> deleteDocument(String documentId) {
    return database.transaction(() async {
      await (database.delete(database.changes)
            ..where((row) => row.documentId.equals(documentId)))
          .go();
      await (database.delete(database.snapshots)
            ..where((row) => row.documentId.equals(documentId)))
          .go();
      await (database.delete(database.peers)
            ..where((row) => row.documentId.equals(documentId)))
          .go();
    });
  }

  /// Closes the underlying database and releases its resources.
  ///
  /// Closing twice is not an error: the second call does nothing.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await database.close();
  }
}
