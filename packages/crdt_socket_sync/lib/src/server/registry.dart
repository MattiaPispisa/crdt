import 'package:crdt_lf/crdt_lf.dart';

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Get or create a store for a document
  CRDTDocument getOrCreate(
    String documentId, {
    CRDTDocument? initialDocument,
  });

  /// Get a store for an existing document
  CRDTDocument? get(String documentId);

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

  /// Apply a change to a document
  bool applyChange(String documentId, Change change);
}
