import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// A [CRDTDocumentStorage] that keeps everything in memory.
///
/// The test double every suite in this monorepo runs on, and what the
/// conformance suite checks itself against. Nothing survives the process.
///
/// Every method answers without suspending, so this is also what the
/// synchronous half of the contract — [CRDTDocumentPersistence.openSync] — is
/// checked against.
class InMemoryDocumentStorage extends CRDTDocumentStorage {
  /// Creates an empty storage for [documentId].
  InMemoryDocumentStorage(String documentId)
      : super(
          changes: InMemoryChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );
}

/// The [CRDTChangeStorage] of an [InMemoryDocumentStorage].
class InMemoryChangeStorage implements CRDTChangeStorage {
  /// Creates an empty change storage for [documentId].
  InMemoryChangeStorage(this.documentId);

  @override
  final String documentId;

  final Map<String, Change> _changes = <String, Change>{};

  @override
  void saveChange(Change change) {
    _changes[change.id.toString()] = change;
  }

  @override
  void saveChanges(List<Change> changes) {
    for (final change in changes) {
      _changes[change.id.toString()] = change;
    }
  }

  @override
  List<Change> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) {
    return filterByVersion(
      _changes.values.toList(),
      newerThan: newerThan,
      upTo: upTo,
    );
  }

  @override
  bool deleteChange(Change change) =>
      _changes.remove(change.id.toString()) != null;

  @override
  int deleteChanges(List<Change> changes) {
    var deleted = 0;
    for (final change in changes) {
      if (_changes.remove(change.id.toString()) != null) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  void clear() => _changes.clear();

  @override
  int get count => _changes.length;
}

/// The [CRDTSnapshotStorage] of an [InMemoryDocumentStorage].
class InMemorySnapshotStorage implements CRDTSnapshotStorage {
  /// Creates an empty snapshot storage for [documentId].
  InMemorySnapshotStorage(this.documentId);

  @override
  final String documentId;

  final Map<String, Snapshot> _snapshots = <String, Snapshot>{};

  @override
  void saveSnapshot(Snapshot snapshot) {
    _snapshots[snapshot.id] = snapshot;
  }

  @override
  void saveSnapshots(List<Snapshot> snapshots) {
    for (final snapshot in snapshots) {
      _snapshots[snapshot.id] = snapshot;
    }
  }

  @override
  Snapshot? getSnapshot(String id) => _snapshots[id];

  @override
  List<Snapshot> getSnapshots() => _snapshots.values.toList();

  @override
  bool containsSnapshot(String id) => _snapshots.containsKey(id);

  @override
  bool deleteSnapshot(String id) => _snapshots.remove(id) != null;

  @override
  int deleteSnapshots(List<String> ids) {
    var deleted = 0;
    for (final id in ids) {
      if (_snapshots.remove(id) != null) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  void clear() => _snapshots.clear();

  @override
  int get count => _snapshots.length;
}

/// The [CRDTPeerIdStorage] of an [InMemoryDocumentStorage].
class InMemoryPeerIdStorage implements CRDTPeerIdStorage {
  /// Creates a peer id storage for [documentId].
  ///
  /// [peers] is where the identities are kept. Without it they go in a map
  /// shared by every instance of this class, so two storages of one process
  /// see each other's the way two openings of one database would.
  InMemoryPeerIdStorage(this.documentId, [Map<String, PeerId>? peers])
      : _peers = peers ?? _shared;

  static final Map<String, PeerId> _shared = <String, PeerId>{};

  /// Forgets every identity kept in the shared map.
  static void reset() => _shared.clear();

  @override
  final String documentId;

  final Map<String, PeerId> _peers;

  @override
  PeerId? getPeerId() => _peers[documentId];

  @override
  void savePeerId(PeerId peerId) {
    _peers[documentId] = peerId;
  }
}

/// A [CRDTStorageBackend] that keeps everything in memory.
///
/// The whole contract, one process wide: documents, their storages and their
/// identities. Nothing survives the process, so a suite that reopens it is
/// told to skip.
///
/// Every method answers without suspending.
class InMemoryStorageBackend implements CRDTStorageBackend {
  final Map<String, InMemoryDocumentStorage> _documents =
      <String, InMemoryDocumentStorage>{};

  final Map<String, PeerId> _peers = <String, PeerId>{};

  @override
  InMemoryDocumentStorage storageForDocument(String documentId) {
    return _documents.putIfAbsent(
      documentId,
      () => InMemoryDocumentStorage(documentId),
    );
  }

  @override
  InMemoryPeerIdStorage peerIdStorageForDocument(String documentId) {
    return InMemoryPeerIdStorage(documentId, _peers);
  }

  @override
  Set<String> get documentIds => <String>{..._documents.keys, ..._peers.keys};

  @override
  void deleteDocument(String documentId) {
    _documents.remove(documentId);
    _peers.remove(documentId);
  }

  @override
  void close() {}
}
