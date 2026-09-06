import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';

/// {@template in_memory_crdt_server_registry}
/// In-memory implementation of [CRDTServerRegistry].
///
/// This implementation stores all documents in memory using a [Map].
/// Documents are lost when the server restarts.
/// {@endtemplate}
class InMemoryCRDTServerRegistry
    with CRDTServerRegistryDocuments
    implements CRDTServerRegistry {
  /// {@macro in_memory_crdt_server_registry}
  ///
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
  Future<void> addDocument(
    String documentId, {
    PeerId? author,
  }) async {
    _documents[documentId] = CRDTDocument(
      peerId: author ?? PeerId.generate(),
    );
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

  /// Keeps the snapshot [createSnapshot] just took, so [getLatestSnapshot]
  /// can hand it back. There is nowhere else for it to go.
  @override
  Future<void> afterSnapshot(String documentId, Snapshot snapshot) async {
    _snapshots[documentId] = snapshot;
  }

  @override
  Future<Snapshot?> getLatestSnapshot(String documentId) async {
    return _snapshots[documentId];
  }

  /// Disposes every document and forgets it.
  ///
  /// Nothing is written: this registry has nowhere to write to, and says so.
  @override
  Future<void> close() async {
    for (final document in _documents.values) {
      document.dispose();
    }
    await clear();
  }

  /// Clear all documents and snapshots
  Future<void> clear() async {
    _documents.clear();
    _snapshots.clear();
  }

  /// Get a copy of all documents (for debugging/testing purposes)
  Map<String, CRDTDocument> get documents => Map.unmodifiable(_documents);

  /// Get a copy of all snapshots (for debugging/testing purposes)
  ///
  /// Named for what it holds, not `snapshots`: the durable registry uses that
  /// name for a stream of the snapshots as they are taken, and one name for
  /// two unrelated things on one interface is a trap.
  Map<String, Snapshot> get snapshotsByDocument => Map.unmodifiable(_snapshots);
}
