import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Stores [Snapshot] objects in a Hive [box].
///
/// The box holds one document: [CRDTHive.openSnapshotStorageForDocument]
/// names it after the document id, so nothing filters by document here.
class CRDTHiveSnapshotStorage implements CRDTSnapshotStorage {
  /// Creates a new [CRDTHiveSnapshotStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Snapshot] objects.
  ///
  /// [documentId] is the unique identifier
  /// for the document these snapshots belong to.
  CRDTHiveSnapshotStorage(this.box, this.documentId);

  /// The Hive box used for storing [Snapshot] objects.
  final Box<Snapshot> box;

  @override
  final String documentId;

  /// Generates a composite key for storing snapshots by document.
  String _getSnapshotKey(String snapshotId) => snapshotId;

  @override
  Future<void> saveSnapshot(Snapshot snapshot) {
    final key = _getSnapshotKey(snapshot.id);
    return box.put(key, snapshot).then((_) => null);
  }

  @override
  Future<void> saveSnapshots(List<Snapshot> snapshots) {
    final entries = <String, Snapshot>{};
    for (final snapshot in snapshots) {
      final key = _getSnapshotKey(snapshot.id);
      entries[key] = snapshot;
    }
    return box.putAll(entries).then((_) => null);
  }

  @override
  Future<Snapshot?> getSnapshot(String id) async {
    final key = _getSnapshotKey(id);
    return box.get(key);
  }

  @override
  Future<List<Snapshot>> getSnapshots() async {
    return box.values.toList();
  }

  @override
  Future<bool> deleteSnapshot(String id) async {
    final key = _getSnapshotKey(id);
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  @override
  Future<int> deleteSnapshots(List<String> ids) async {
    final existingKeys =
        ids.map(_getSnapshotKey).where(box.containsKey).toList();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  @override
  Future<void> clear() {
    return box.clear();
  }

  @override
  Future<int> get count async => box.length;

  @override
  Future<bool> containsSnapshot(String id) async {
    final key = _getSnapshotKey(id);
    return box.containsKey(key);
  }
}
