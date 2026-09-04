import 'dart:io';

import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_drift/src/storage/change_storage.dart';
import 'package:crdt_lf_drift/src/storage/document_storage.dart';
import 'package:crdt_lf_drift/src/storage/peer_id_storage.dart';
import 'package:crdt_lf_drift/src/storage/snapshot_storage.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Main utility class for persisting CRDT objects in a drift database.
///
/// A single [CRDTDrift] instance wraps one [CRDTDriftDatabase] holding two
/// tables (`changes` and `snapshots`). Data for different documents lives in
/// the same tables and is isolated through the `document_id` column, so you
/// can persist any number of documents in a single database.
///
/// ```dart
/// final storage = CRDTDrift.open(File('app.db'));
/// final changes = storage.changeStorageForDocument('doc-1');
/// ...
/// await storage.close();
/// ```
class CRDTDrift {
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
  CRDTDriftPeerIdStorage peerIdStorageForDocument(String documentId) {
    return CRDTDriftPeerIdStorage(database, documentId);
  }

  /// Creates both change and snapshot storage for [documentId], bundled in a
  /// [CRDTDriftDocumentStorage].
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
  Future<void> deleteDocumentData(String documentId) {
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
  Future<void> close() {
    return database.close();
  }
}
