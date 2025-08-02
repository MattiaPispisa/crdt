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
  Future<void> addDocument(String documentId) async {
    _documents[documentId] = CRDTDocument(peerId: PeerId.parse(documentId));
  }

  @override
  Future<CRDTDocument?> getDocument(String documentId) async {
    return _documents[documentId];
  }

  @override
  Future<bool> hasDocument(String documentId) async {
    return _documents.containsKey(documentId);
  }

  @override
  Future<void> removeDocument(String documentId) async {
    _documents.remove(documentId);
    _snapshots.remove(documentId);
  }

  @override
  Future<Set<String>> get documentIds async {
    return _documents.keys.toSet();
  }

  @override
  Future<int> get documentCount async {
    return _documents.length;
  }

  @override
  Future<Snapshot> createSnapshot(String documentId) async {
    final document = _documents[documentId];
    if (document == null) {
      throw ArgumentError('Document with ID "$documentId" not found');
    }

    final snapshot = document.takeSnapshot();
    _snapshots[documentId] = snapshot;
    return snapshot;
  }

  @override
  Future<Snapshot?> getLatestSnapshot(String documentId) async {
    return _snapshots[documentId];
  }

  @override
  Future<bool> applyChange(String documentId, Change change) async {
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
  Future<void> clear() async {
    _documents.clear();
    _snapshots.clear();
  }

  /// Get a copy of all documents (for debugging/testing purposes)
  Map<String, CRDTDocument> get documents => Map.unmodifiable(_documents);

  /// Get a copy of all snapshots (for debugging/testing purposes)
  Map<String, Snapshot> get snapshots => Map.unmodifiable(_snapshots);
}
