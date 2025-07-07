import 'package:crdt_lf/crdt_lf.dart';
import 'package:hive/hive.dart';

/// Storage utility for managing [Snapshot] objects in [Hive].
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects in a Hive box.
class CRDTSnapshotStorage {
  /// Creates a new [CRDTSnapshotStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Snapshot] objects.
  ///
  /// [documentId] is the unique identifier
  /// for the document these snapshots belong to.
  CRDTSnapshotStorage(this.box, this.documentId);

  /// The Hive box used for storing [Snapshot] objects.
  final Box<Snapshot> box;

  /// The unique identifier for the document these snapshots belong to.
  final String documentId;

  /// Generates a composite key for storing snapshots by document.
  String _getSnapshotKey(String snapshotId) => snapshotId;

  /// Saves a [Snapshot] to the storage.
  Future<void> saveSnapshot(Snapshot snapshot) {
    final key = _getSnapshotKey(snapshot.id);
    return box.put(key, snapshot).then((_) => null);
  }

  /// Saves multiple [Snapshot] objects to the storage.
  ///
  /// This method is more efficient than calling [saveSnapshot] multiple times
  /// as it performs batch operations.
  Future<void> saveSnapshots(List<Snapshot> snapshots) {
    final entries = <String, Snapshot>{};
    for (final snapshot in snapshots) {
      final key = _getSnapshotKey(snapshot.id);
      entries[key] = snapshot;
    }
    return box.putAll(entries).then((_) => null);
  }

  /// Retrieves a [Snapshot] by its ID.
  ///
  /// Returns the [Snapshot] if found, or null if not found.
  Snapshot? getSnapshot(String id) {
    final key = _getSnapshotKey(id);
    return box.get(key);
  }

  /// Retrieves all [Snapshot] objects from the storage for this document.
  ///
  /// Returns a list of all stored snapshots for this document.
  List<Snapshot> getSnapshots() {
    return box.values.toList();
  }

  /// Deletes a [Snapshot] by its ID.
  ///
  /// Returns true if the snapshot was found and deleted, false otherwise.
  Future<bool> deleteSnapshot(String id) async {
    final key = _getSnapshotKey(id);
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  /// Deletes multiple [Snapshot] objects by their IDs.
  ///
  /// Returns the number of snapshots that were actually deleted.
  Future<int> deleteSnapshots(List<String> ids) async {
    final existingKeys = ids
        .map(_getSnapshotKey)
        .where(box.containsKey)
        .toList();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  /// Clears all [Snapshot] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() {
    return box.clear();
  }

  /// Returns the number of [Snapshot] objects for this document in the storage.
  int get count => box.length;

  /// Returns true if the storage is empty for this document.
  bool get isEmpty => box.isEmpty;

  /// Returns true if the storage is not empty for this document.
  bool get isNotEmpty => box.isNotEmpty;

  /// Checks if a [Snapshot] with the given ID exists for this document.
  bool containsSnapshot(String id) {
    final key = _getSnapshotKey(id);
    return box.containsKey(key);
  }
}
