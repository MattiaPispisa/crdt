import 'package:crdt_lf/crdt_lf.dart';

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Register a document
  Future<void> addDocument(String documentId);

  /// Get a store for an existing document
  Future<CRDTDocument?> getDocument(String documentId);

  /// Check if a document exists
  Future<bool> hasDocument(String documentId);

  /// Remove a document
  Future<void> removeDocument(String documentId);

  /// Get all document IDs
  Future<Set<String>> get documentIds;

  /// Get the number of documents registered
  Future<int> get documentCount;

  /// Create a snapshot of a document
  Future<Snapshot> createSnapshot(String documentId);

  /// Get the latest snapshot of a document
  Future<Snapshot?> getLatestSnapshot(String documentId);

  /// Apply a change to a document
  Future<bool> applyChange(String documentId, Change change);
}
