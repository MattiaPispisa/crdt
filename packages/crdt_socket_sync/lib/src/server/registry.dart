import 'package:crdt_lf/crdt_lf.dart';

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Register a document
  void addDocument(String documentId, CRDTDocument document);

  /// Get a store for an existing document
  CRDTDocument? getDocument(String documentId);

  /// Check if a document exists
  bool hasDocument(String documentId);

  /// Remove a document
  void removeDocument(String documentId);

  /// Get all document IDs
  Set<String> get documentIds;

  /// Get the number of documents registered
  int get documentCount;

  /// Create a snapshot of a document
  Snapshot createSnapshot(String documentId);

  /// Get the latest snapshot of a document
  Snapshot? getLatestSnapshot(String documentId);

  /// Apply a change to a document
  bool applyChange(String documentId, Change change);
}
