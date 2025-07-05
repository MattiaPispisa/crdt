import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Storage utility for managing [Snapshot] objects in Hive.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects in a Hive box.
class CRDTSnapshotStorage {
  /// Creates a new [CRDTSnapshotStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Snapshot] objects.
  CRDTSnapshotStorage(this.box);

  /// The Hive box used for storing [Snapshot] objects.
  final Box<Snapshot> box;

  /// Saves a [Snapshot] to the storage.
  ///
  /// The snapshot is stored using its ID as the key.
  /// Returns the key that was used to store the snapshot.
  Future<String> saveSnapshot(Snapshot snapshot) async {
    await box.put(snapshot.id, snapshot);
    return snapshot.id;
  }

  /// Saves multiple [Snapshot] objects to the storage.
  ///
  /// This method is more efficient than calling [saveSnapshot] multiple times
  /// as it performs batch operations.
  /// Returns a list of keys that were used to store the snapshots.
  Future<List<String>> saveSnapshots(List<Snapshot> snapshots) async {
    final entries = <String, Snapshot>{};
    for (final snapshot in snapshots) {
      entries[snapshot.id] = snapshot;
    }
    await box.putAll(entries);
    return entries.keys.toList();
  }

  /// Retrieves a [Snapshot] by its ID.
  ///
  /// Returns the [Snapshot] if found, or null if not found.
  Snapshot? getSnapshot(String id) {
    return box.get(id);
  }

  /// Retrieves all [Snapshot] objects from the storage.
  ///
  /// Returns a list of all stored snapshots.
  List<Snapshot> getAllSnapshots() {
    return box.values.toList();
  }

  /// Retrieves snapshots by a specific peer.
  ///
  /// Returns snapshots that contain the specified [PeerId] in their version vector.
  List<Snapshot> getSnapshotsByPeer(PeerId peerId) {
    return box.values.where((snapshot) {
      return snapshot.versionVector[peerId] != null;
    }).toList();
  }

  /// Retrieves the most recent snapshot for a specific peer.
  ///
  /// Returns the snapshot with the highest clock value for the specified [PeerId],
  /// or null if no snapshots contain this peer.
  Snapshot? getMostRecentSnapshotForPeer(PeerId peerId) {
    final snapshots = getSnapshotsByPeer(peerId);
    if (snapshots.isEmpty) return null;
    
    return snapshots.reduce((a, b) {
      final aTime = a.versionVector[peerId]!;
      final bTime = b.versionVector[peerId]!;
      return aTime.compareTo(bTime) > 0 ? a : b;
    });
  }

  /// Retrieves snapshots that are newer than a given version vector.
  ///
  /// Returns snapshots whose version vector is strictly newer than the provided one.
  List<Snapshot> getSnapshotsNewerThan(VersionVector versionVector) {
    return box.values.where((snapshot) {
      return snapshot.versionVector.isStrictlyNewerThan(versionVector);
    }).toList();
  }

  /// Retrieves snapshots that are newer or equal to a given version vector.
  ///
  /// Returns snapshots whose version vector is strictly newer or equal to the provided one.
  List<Snapshot> getSnapshotsNewerOrEqualThan(VersionVector versionVector) {
    return box.values.where((snapshot) {
      return snapshot.versionVector.isStrictlyNewerOrEqualThan(versionVector);
    }).toList();
  }

  /// Finds the best snapshot for a given version vector.
  ///
  /// Returns the snapshot that is closest to (but not newer than) the given version vector.
  /// This is useful for finding a good starting point for applying changes.
  Snapshot? getBestSnapshotForVersion(VersionVector targetVersion) {
    final candidates = box.values.where((snapshot) {
      return targetVersion.isStrictlyNewerOrEqualThan(snapshot.versionVector);
    }).toList();
    
    if (candidates.isEmpty) return null;
    
    // Find the snapshot with the most recent overall timestamp
    return candidates.reduce((a, b) {
      final aMostRecent = _getMostRecentClock(a.versionVector);
      final bMostRecent = _getMostRecentClock(b.versionVector);
      
      if (aMostRecent == null && bMostRecent == null) return a;
      if (aMostRecent == null) return b;
      if (bMostRecent == null) return a;
      
      return aMostRecent.compareTo(bMostRecent) > 0 ? a : b;
    });
  }

  /// Helper method to get the most recent clock from a version vector.
  HybridLogicalClock? _getMostRecentClock(VersionVector versionVector) {
    if (versionVector.isEmpty) return null;
    
    HybridLogicalClock? mostRecent;
    for (final entry in versionVector.entries) {
      if (mostRecent == null || entry.value.compareTo(mostRecent) > 0) {
        mostRecent = entry.value;
      }
    }
    return mostRecent;
  }

  /// Deletes a [Snapshot] by its ID.
  ///
  /// Returns true if the snapshot was found and deleted, false otherwise.
  Future<bool> deleteSnapshot(String id) async {
    if (box.containsKey(id)) {
      await box.delete(id);
      return true;
    }
    return false;
  }

  /// Deletes multiple [Snapshot] objects by their IDs.
  ///
  /// Returns the number of snapshots that were actually deleted.
  Future<int> deleteSnapshots(List<String> ids) async {
    final existingIds = ids.where((id) => box.containsKey(id)).toList();
    await box.deleteAll(existingIds);
    return existingIds.length;
  }

  /// Deletes old snapshots, keeping only the most recent ones.
  ///
  /// [keepCount] specifies how many of the most recent snapshots to keep.
  /// Snapshots are ordered by their most recent clock value.
  /// Returns the number of snapshots that were deleted.
  Future<int> deleteOldSnapshots({required int keepCount}) async {
    final allSnapshots = getAllSnapshots();
    if (allSnapshots.length <= keepCount) return 0;
    
    // Sort by most recent clock value (descending)
    allSnapshots.sort((a, b) {
      final aMostRecent = _getMostRecentClock(a.versionVector);
      final bMostRecent = _getMostRecentClock(b.versionVector);
      
      if (aMostRecent == null && bMostRecent == null) return 0;
      if (aMostRecent == null) return 1;
      if (bMostRecent == null) return -1;
      
      return bMostRecent.compareTo(aMostRecent);
    });
    
    // Keep the most recent ones, delete the rest
    final toDelete = allSnapshots.skip(keepCount).map((s) => s.id).toList();
    await box.deleteAll(toDelete);
    return toDelete.length;
  }

  /// Clears all [Snapshot] objects from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() async {
    await box.clear();
  }

  /// Returns the number of [Snapshot] objects in the storage.
  int get count => box.length;

  /// Returns true if the storage is empty.
  bool get isEmpty => box.isEmpty;

  /// Returns true if the storage is not empty.
  bool get isNotEmpty => box.isNotEmpty;

  /// Returns all keys in the storage.
  Iterable<String> get keys => box.keys.cast<String>();

  /// Checks if a [Snapshot] with the given ID exists.
  bool containsSnapshot(String id) {
    return box.containsKey(id);
  }

  /// Gets the most recent [Snapshot] by overall timestamp.
  ///
  /// Returns the snapshot with the highest overall clock value,
  /// or null if the storage is empty.
  Snapshot? getMostRecentSnapshot() {
    if (isEmpty) return null;
    
    return box.values.reduce((a, b) {
      final aMostRecent = _getMostRecentClock(a.versionVector);
      final bMostRecent = _getMostRecentClock(b.versionVector);
      
      if (aMostRecent == null && bMostRecent == null) return a;
      if (aMostRecent == null) return b;
      if (bMostRecent == null) return a;
      
      return aMostRecent.compareTo(bMostRecent) > 0 ? a : b;
    });
  }

  /// Gets the oldest [Snapshot] by overall timestamp.
  ///
  /// Returns the snapshot with the lowest overall clock value,
  /// or null if the storage is empty.
  Snapshot? getOldestSnapshot() {
    if (isEmpty) return null;
    
    return box.values.reduce((a, b) {
      final aMostRecent = _getMostRecentClock(a.versionVector);
      final bMostRecent = _getMostRecentClock(b.versionVector);
      
      if (aMostRecent == null && bMostRecent == null) return a;
      if (aMostRecent == null) return a;
      if (bMostRecent == null) return b;
      
      return aMostRecent.compareTo(bMostRecent) < 0 ? a : b;
    });
  }

  /// Gets snapshots sorted by overall timestamp.
  ///
  /// Returns all snapshots sorted by their most recent clock value in ascending order.
  List<Snapshot> getSnapshotsSortedByTime() {
    final snapshots = getAllSnapshots();
    snapshots.sort((a, b) {
      final aMostRecent = _getMostRecentClock(a.versionVector);
      final bMostRecent = _getMostRecentClock(b.versionVector);
      
      if (aMostRecent == null && bMostRecent == null) return 0;
      if (aMostRecent == null) return -1;
      if (bMostRecent == null) return 1;
      
      return aMostRecent.compareTo(bMostRecent);
    });
    return snapshots;
  }
} 