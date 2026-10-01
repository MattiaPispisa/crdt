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
  }) : this._(
          documents ?? <String, CRDTDocument>{},
          snapshots ?? <String, Snapshot>{},
        );

  InMemoryCRDTServerRegistry._(this._documents, this._snapshots)
      : _feed = DocumentSnapshotFeed() {
    _startSnapshots();
  }

  /// Internal storage for documents
  final Map<String, CRDTDocument> _documents;

  /// Internal storage for snapshots
  final Map<String, Snapshot> _snapshots;

  final DocumentSnapshotFeed _feed;

  @override
  Future<void> addDocument(
    String documentId, {
    PeerId? author,
  }) async {
    final document = _documents[documentId] = CRDTDocument(
      documentId: documentId,
      peerId: author ?? PeerId.generate(),
    );
    _feed.track(documentId, document);
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
    await _feed.untrack(documentId);
    _documents.remove(documentId);
    _snapshots.remove(documentId);
  }

  @override
  Future<Set<String>> get documentIds async {
    return _documents.keys.toSet();
  }

  @override
  Stream<ServerSnapshot> get snapshots => _feed.snapshots;

  void _startSnapshots() {
    _documents.forEach(_feed.track);
    _feed.start(
      onSnapshot: (taken) => _snapshots[taken.documentId] = taken.snapshot,
    );
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
    await _feed.close();
  }

  /// Clear all documents and snapshots
  Future<void> clear() async {
    for (final documentId in List.of(_documents.keys)) {
      await _feed.untrack(documentId);
    }
    _documents.clear();
    _snapshots.clear();
  }

  /// Get a copy of all documents (for debugging/testing purposes)
  Map<String, CRDTDocument> get documents => Map.unmodifiable(_documents);

  /// Get a copy of all snapshots (for debugging/testing purposes)
  ///
  /// The latest snapshot of each document; [snapshots] streams them as they
  /// are taken.
  Map<String, Snapshot> get snapshotsByDocument => Map.unmodifiable(_snapshots);
}
