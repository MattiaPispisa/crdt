import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:drift/drift.dart';

/// Storage utility for managing [Snapshot] objects in a drift database.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Snapshot] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTDriftSnapshotStorage implements CRDTSnapshotStorage {
  /// Creates a new [CRDTDriftSnapshotStorage] instance.
  ///
  /// [database] is the drift database used to store [Snapshot] objects.
  ///
  /// [documentId] is the unique identifier for the document these snapshots
  /// belong to.
  CRDTDriftSnapshotStorage(this.database, this.documentId);

  /// The drift database used for storing [Snapshot] objects.
  final CRDTDriftDatabase database;

  @override
  final String documentId;

  SnapshotsCompanion _companion(Snapshot snapshot) {
    return SnapshotsCompanion.insert(
      documentId: documentId,
      snapshotId: snapshot.id,
      bytes: snapshot.toBytes(),
    );
  }

  @override
  Future<void> saveSnapshot(Snapshot snapshot) {
    return database
        .into(database.snapshots)
        .insertOnConflictUpdate(_companion(snapshot));
  }

  @override
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

  @override
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

  @override
  Future<List<Snapshot>> getSnapshots() async {
    final query = database.select(database.snapshots)
      ..where((row) => row.documentId.equals(documentId));
    final rows = await query.get();
    return rows.map((row) => Snapshot.fromBytes(row.bytes)).toList();
  }

  @override
  Future<bool> deleteSnapshot(String id) async {
    final deleted = await (database.delete(database.snapshots)
          ..where(
            (row) =>
                row.documentId.equals(documentId) & row.snapshotId.equals(id),
          ))
        .go();
    return deleted > 0;
  }

  @override
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

  @override
  Future<void> clear() async {
    await (database.delete(database.snapshots)
          ..where((row) => row.documentId.equals(documentId)))
        .go();
  }

  @override
  Future<bool> containsSnapshot(String id) async {
    return (await getSnapshot(id)) != null;
  }

  @override
  Future<int> get count async {
    final countExp = database.snapshots.snapshotId.count();
    final query = database.selectOnly(database.snapshots)
      ..addColumns([countExp])
      ..where(database.snapshots.documentId.equals(documentId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
