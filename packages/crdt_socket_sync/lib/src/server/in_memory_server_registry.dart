import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server/registry.dart';

/// In-memory implementation of [CRDTServerRegistry].
///
/// This implementation stores all documents in memory using a [Map].
/// Documents are lost when the server restarts.
class InMemoryCRDTServerRegistry implements CRDTServerRegistry {
  /// Creates a new [InMemoryCRDTServerRegistry]
  InMemoryCRDTServerRegistry({
    Map<String, CRDTDocument>? documents,
    Map<String, Snapshot>? snapshots,
  })  : _documents = documents ?? <String, CRDTDocument>{},
        _snapshots = snapshots ?? <String, Snapshot>{};

  /// Internal storage for documents
  final Map<String, CRDTDocument> _documents;

  /// Internal storage for snapshots
  final Map<String, Snapshot> _snapshots;

  @override
  void addDocument(String documentId, CRDTDocument document) {
    _documents[documentId] = document;
  }

  @override
  CRDTDocument? getDocument(String documentId) {
    return _documents[documentId];
  }

  @override
  bool hasDocument(String documentId) {
    return _documents.containsKey(documentId);
  }

  @override
  void removeDocument(String documentId) {
    _documents.remove(documentId);
    _snapshots.remove(documentId);
  }

  @override
  Set<String> get documentIds => _documents.keys.toSet();

  @override
  int get documentCount => _documents.length;

  @override
  Snapshot createSnapshot(String documentId) {
    final document = _documents[documentId];
    if (document == null) {
      throw ArgumentError('Document with ID "$documentId" not found');
    }

    final snapshot = document.takeSnapshot();
    _snapshots[documentId] = snapshot;
    return snapshot;
  }

  @override
  Snapshot? getLatestSnapshot(String documentId) {
    return _snapshots[documentId];
  }

  @override
  bool applyChange(String documentId, Change change) {
    final document = _documents[documentId];
    if (document == null) {
      throw ArgumentError('Document with ID "$documentId" not found');
    }

    try {
      return document.applyChange(change);
    } catch (e) {
      // Change could not be applied (e.g., not causally ready)
      return false;
    }
  }

  /// Clear all documents and snapshots
  void clear() {
    _documents.clear();
    _snapshots.clear();
  }

  /// Get a copy of all documents (for debugging/testing purposes)
  Map<String, CRDTDocument> get documents => Map.unmodifiable(_documents);

  /// Get a copy of all snapshots (for debugging/testing purposes)
  Map<String, Snapshot> get snapshots => Map.unmodifiable(_snapshots);
}
