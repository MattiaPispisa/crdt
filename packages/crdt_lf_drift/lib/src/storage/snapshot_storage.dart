import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/snapshots_table.dart';

/// Storage utility for managing [Snapshot] objects in Drift.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects in a Drift database.
class CRDTSnapshotStorage {
  /// Creates a new [CRDTSnapshotStorage] instance.
  ///
  /// [database] is the Drift database that will be used to store [Snapshot] objects.
  /// [documentId] is the unique identifier for the document these snapshots belong to.
  CRDTSnapshotStorage(this.database, this.documentId);

  /// The Drift database used for storing [Snapshot] objects.
  final CRDTDatabase database;

  /// The unique identifier for the document these snapshots belong to.
  final String documentId;

  /// Generates a composite key for storing snapshots by document.
  String _getSnapshotKey(String snapshotId) => snapshotId;

  /// Converts a [Snapshot] to a [SnapshotsCompanion] for database insertion.
  SnapshotsCompanion _snapshotToCompanion(Snapshot snapshot) {
    final key = '${documentId}_${snapshot.id}';
    return SnapshotsCompanion.insert(
      id: key,
      documentId: documentId,
      snapshotId: snapshot.id,
      versionVector: snapshot.versionVector,
      data: json.encode(snapshot.data),
    );
  }

  /// Converts a [SnapshotEntity] from database to a [Snapshot].
  Snapshot _entityToSnapshot(SnapshotEntity entity) {
    final data = json.decode(entity.data) as Map<String, dynamic>;
    
    return Snapshot(
      id: entity.snapshotId,
      versionVector: entity.versionVector,
      data: data,
    );
  }

  /// Saves a [Snapshot] to the storage.
  Future<void> saveSnapshot(Snapshot snapshot) {
    return database.into(database.snapshots).insert(_snapshotToCompanion(snapshot));
  }

  /// Saves multiple [Snapshot] objects to the storage.
  ///
  /// This method is more efficient than calling [saveSnapshot] multiple times
  /// as it performs batch operations.
  Future<void> saveSnapshots(List<Snapshot> snapshots) {
    return database.batch((batch) {
      for (final snapshot in snapshots) {
        batch.insert(database.snapshots, _snapshotToCompanion(snapshot));
      }
    });
  }

  /// Retrieves a [Snapshot] by its ID.
  ///
  /// Returns the [Snapshot] if found, or null if not found.
  Future<Snapshot?> getSnapshot(String snapshotId) async {
    final query = database.select(database.snapshots)
      ..where((tbl) => 
          tbl.documentId.equals(documentId) & 
          tbl.snapshotId.equals(snapshotId))
      ..limit(1);

    final entities = await query.get();
    if (entities.isEmpty) return null;
    
    return _entityToSnapshot(entities.first);
  }

  /// Retrieves all [Snapshot] objects from the storage for this document.
  Future<List<Snapshot>> getSnapshots() async {
    final query = database.select(database.snapshots)
      ..where((tbl) => tbl.documentId.equals(documentId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);

    final entities = await query.get();
    return entities.map(_entityToSnapshot).toList();
  }

  /// Deletes a [Snapshot] by its ID.
  ///
  /// Returns true if the snapshot was found and deleted, false otherwise.
  Future<bool> deleteSnapshot(String snapshotId) async {
    final deletedRows = await (database.delete(database.snapshots)
          ..where((tbl) => 
              tbl.documentId.equals(documentId) & 
              tbl.snapshotId.equals(snapshotId)))
        .go();
    return deletedRows > 0;
  }

  /// Deletes multiple [Snapshot] objects by their IDs.
  ///
  /// Returns the number of snapshots that were actually deleted.
  Future<int> deleteSnapshots(List<String> snapshotIds) async {
    return await (database.delete(database.snapshots)
          ..where((tbl) => 
              tbl.documentId.equals(documentId) & 
              tbl.snapshotId.isIn(snapshotIds)))
        .go();
  }

  /// Clears all [Snapshot] objects for this document from the storage.
  Future<void> clear() {
    return (database.delete(database.snapshots)
          ..where((tbl) => tbl.documentId.equals(documentId)))
        .go()
        .then((_) => null);
  }

  /// Returns the number of [Snapshot] objects for this document in the storage.
  Future<int> get count async {
    final query = database.selectOnly(database.snapshots)
      ..addColumns([database.snapshots.id.count()])
      ..where(database.snapshots.documentId.equals(documentId));

    final result = await query.getSingle();
    return result.read(database.snapshots.id.count()) ?? 0;
  }

  /// Returns true if the storage is empty for this document.
  Future<bool> get isEmpty async => (await count) == 0;

  /// Returns true if the storage is not empty for this document.
  Future<bool> get isNotEmpty async => (await count) > 0;

  /// Checks if a [Snapshot] with the given ID exists for this document.
  Future<bool> containsSnapshot(String snapshotId) async {
    final snapshot = await getSnapshot(snapshotId);
    return snapshot != null;
  }

  /// Stream of snapshots for this document.
  Stream<List<Snapshot>> watchSnapshots() {
    final query = database.select(database.snapshots)
      ..where((tbl) => tbl.documentId.equals(documentId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);

    return query.watch().map((entities) => entities.map(_entityToSnapshot).toList());
  }
} 