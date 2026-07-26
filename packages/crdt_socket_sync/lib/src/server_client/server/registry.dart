import 'package:crdt_lf/crdt_lf.dart';

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Register a document
  Future<void> addDocument(
    String documentId, {
    PeerId? author,
  });

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

  /// Apply a change to a document.
  ///
  /// Returns `true` if the change was applied, `false` if it was a duplicate
  /// (already known).
  ///
  /// Implementations MUST let [CausallyNotReadyException] propagate when the
  /// change depends on operations the document does not have (and that are not
  /// covered by a snapshot). The server relies on this to detect an
  /// out-of-sync client and trigger a re-sync; swallowing it would silently
  /// drop the change.
  Future<bool> applyChange(String documentId, Change change);
}
