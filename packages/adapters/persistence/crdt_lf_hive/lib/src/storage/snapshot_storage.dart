import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Stores [Snapshot] objects in a Hive [box].
///
/// The box holds one document: [CRDTHive.openSnapshotStorageForDocument]
/// names it after the document id, so nothing filters by document here.
///
/// A Hive box keeps its entries in memory, so every read here answers without
/// suspending and says so in its return type. Writes go through the box
/// journal and stay asynchronous.
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

  /// The key a snapshot is stored under.
  ///
  /// The snapshot id, as it is: the box already holds one document, so there
  /// is nothing to scope it by.
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
  Snapshot? getSnapshot(String id) {
    final key = _getSnapshotKey(id);
    return box.get(key);
  }

  @override
  List<Snapshot> getSnapshots() {
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
    // A set, so an id named twice in one batch is counted once: the answer
    // is how many were there, not how many were asked for.
    final existingKeys =
        ids.map(_getSnapshotKey).where(box.containsKey).toSet();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  @override
  Future<void> clear() {
    return box.clear();
  }

  @override
  int get count => box.length;

  @override
  bool containsSnapshot(String id) {
    final key = _getSnapshotKey(id);
    return box.containsKey(key);
  }
}
