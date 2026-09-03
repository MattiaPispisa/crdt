import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// A [CRDTDocumentStorage] that keeps everything in memory.
///
/// For tests, and for the conformance suite to check itself against. Nothing
/// survives the process.
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
  Future<void> saveChange(Change change) async {
    _changes[change.id.toString()] = change;
  }

  @override
  Future<void> saveChanges(List<Change> changes) async {
    for (final change in changes) {
      _changes[change.id.toString()] = change;
    }
  }

  @override
  Future<List<Change>> getChanges() async => _changes.values.toList();

  @override
  Future<bool> deleteChange(Change change) async =>
      _changes.remove(change.id.toString()) != null;

  @override
  Future<int> deleteChanges(List<Change> changes) async {
    var deleted = 0;
    for (final change in changes) {
      if (_changes.remove(change.id.toString()) != null) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  Future<void> clear() async => _changes.clear();

  @override
  Future<int> get count async => _changes.length;
}

/// The [CRDTSnapshotStorage] of an [InMemoryDocumentStorage].
class InMemorySnapshotStorage implements CRDTSnapshotStorage {
  /// Creates an empty snapshot storage for [documentId].
  InMemorySnapshotStorage(this.documentId);

  @override
  final String documentId;

  final Map<String, Snapshot> _snapshots = <String, Snapshot>{};

  @override
  Future<void> saveSnapshot(Snapshot snapshot) async {
    _snapshots[snapshot.id] = snapshot;
  }

  @override
  Future<void> saveSnapshots(List<Snapshot> snapshots) async {
    for (final snapshot in snapshots) {
      _snapshots[snapshot.id] = snapshot;
    }
  }

  @override
  Future<Snapshot?> getSnapshot(String id) async => _snapshots[id];

  @override
  Future<List<Snapshot>> getSnapshots() async => _snapshots.values.toList();

  @override
  Future<bool> containsSnapshot(String id) async => _snapshots.containsKey(id);

  @override
  Future<bool> deleteSnapshot(String id) async => _snapshots.remove(id) != null;

  @override
  Future<int> deleteSnapshots(List<String> ids) async {
    var deleted = 0;
    for (final id in ids) {
      if (_snapshots.remove(id) != null) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  Future<void> clear() async => _snapshots.clear();

  @override
  Future<int> get count async => _snapshots.length;
}
