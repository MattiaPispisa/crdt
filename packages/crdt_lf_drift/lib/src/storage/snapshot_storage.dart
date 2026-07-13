import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:drift/drift.dart';

/// Storage utility for managing [Snapshot] objects in a drift database.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTDriftSnapshotStorage {
  /// Creates a new [CRDTDriftSnapshotStorage] instance.
  ///
  /// [database] is the drift database used to store [Snapshot] objects.
  ///
  /// [documentId] is the unique identifier for the document these snapshots
  /// belong to.
  CRDTDriftSnapshotStorage(this.database, this.documentId);

  /// The drift database used for storing [Snapshot] objects.
  final CRDTDriftDatabase database;

  /// The unique identifier for the document these snapshots belong to.
  final String documentId;

  SnapshotsCompanion _companion(Snapshot snapshot) {
    return SnapshotsCompanion.insert(
      documentId: documentId,
      snapshotId: snapshot.id,
      bytes: snapshot.toBytes(),
    );
  }

  /// Saves a [Snapshot] to the storage.
  ///
  /// If a snapshot with the same id already exists it is overwritten.
  Future<void> saveSnapshot(Snapshot snapshot) {
    return database
        .into(database.snapshots)
        .insertOnConflictUpdate(_companion(snapshot));
  }

  /// Saves multiple [Snapshot] objects to the storage.
  ///
  /// This method is more efficient than calling [saveSnapshot] multiple times
  /// as it performs a single batch.
  Future<void> saveSnapshots(List<Snapshot> snapshots) async {
    if (snapshots.isEmpty) {
      return;
    }
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        database.snapshots,
        snapshots.map(_companion).toList(),
      );
    });
  }

  /// Retrieves a [Snapshot] by its id.
  ///
  /// Returns the [Snapshot] if found, or null otherwise.
  Future<Snapshot?> getSnapshot(String id) async {
    final query = database.select(database.snapshots)
      ..where(
        (row) => row.documentId.equals(documentId) & row.snapshotId.equals(id),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    return Snapshot.fromBytes(row.bytes);
  }

  /// Retrieves all [Snapshot] objects from the storage for this document.
  Future<List<Snapshot>> getSnapshots() async {
    final query = database.select(database.snapshots)
      ..where((row) => row.documentId.equals(documentId));
    final rows = await query.get();
    return rows.map((row) => Snapshot.fromBytes(row.bytes)).toList();
  }

  /// Deletes a [Snapshot] by its id.
  ///
  /// Returns true if the snapshot was found and deleted, false otherwise.
  Future<bool> deleteSnapshot(String id) async {
    final deleted = await (database.delete(database.snapshots)
          ..where(
            (row) =>
                row.documentId.equals(documentId) & row.snapshotId.equals(id),
          ))
        .go();
    return deleted > 0;
  }

  /// Deletes multiple [Snapshot] objects by their ids.
  ///
  /// Returns the number of snapshots that were actually deleted.
  Future<int> deleteSnapshots(List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    return (database.delete(database.snapshots)
          ..where(
            (row) =>
                row.documentId.equals(documentId) & row.snapshotId.isIn(ids),
          ))
        .go();
  }

  /// Clears all [Snapshot] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() async {
    await (database.delete(database.snapshots)
          ..where((row) => row.documentId.equals(documentId)))
        .go();
  }

  /// Checks if a [Snapshot] with the given [id] exists for this document.
  Future<bool> containsSnapshot(String id) async {
    return (await getSnapshot(id)) != null;
  }

  /// Returns the number of [Snapshot] objects for this document in the storage.
  Future<int> get count async {
    final countExp = database.snapshots.snapshotId.count();
    final query = database.selectOnly(database.snapshots)
      ..addColumns([countExp])
      ..where(database.snapshots.documentId.equals(documentId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Returns true if the storage is empty for this document.
  Future<bool> get isEmpty async => (await count) == 0;

  /// Returns true if the storage is not empty for this document.
  Future<bool> get isNotEmpty async => (await count) > 0;
}
