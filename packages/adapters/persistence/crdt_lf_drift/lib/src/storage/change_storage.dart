import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:drift/drift.dart';

/// Storage utility for managing [Change] objects in a drift database.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTDriftChangeStorage implements CRDTChangeStorage {
  /// Creates a new [CRDTDriftChangeStorage] instance.
  ///
  /// [database] is the drift database used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier for the document these changes
  /// belong to.
  CRDTDriftChangeStorage(this.database, this.documentId);

  /// The drift database used for storing [Change] objects.
  final CRDTDriftDatabase database;

  @override
  final String documentId;

  ChangesCompanion _companion(Change change) {
    return ChangesCompanion.insert(
      documentId: documentId,
      changeId: change.id.toString(),
      bytes: change.toBytes(),
    );
  }

  @override
  Future<void> saveChange(Change change) {
    return database
        .into(database.changes)
        .insertOnConflictUpdate(_companion(change));
  }

  @override
  Future<void> saveChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return;
    }
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        database.changes,
        changes.map(_companion).toList(),
      );
    });
  }

  @override
  Future<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) async {
    final query = database.select(database.changes)
      ..where((row) => row.documentId.equals(documentId));
    final rows = await query.get();
    return filterByVersion(
      rows.map((row) => Change.fromBytes(row.bytes)).toList(),
      newerThan: newerThan,
      upTo: upTo,
    );
  }

  @override
  Future<bool> deleteChange(Change change) async {
    final deleted = await (database.delete(database.changes)
          ..where(
            (row) =>
                row.documentId.equals(documentId) &
                row.changeId.equals(change.id.toString()),
          ))
        .go();
    return deleted > 0;
  }

  @override
  Future<int> deleteChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return 0;
    }
    final ids = changes.map((change) => change.id.toString()).toList();
    return (database.delete(database.changes)
          ..where(
            (row) => row.documentId.equals(documentId) & row.changeId.isIn(ids),
          ))
        .go();
  }

  @override
  Future<void> clear() async {
    await (database.delete(database.changes)
          ..where((row) => row.documentId.equals(documentId)))
        .go();
  }

  @override
  Future<int> get count async {
    final countExp = database.changes.changeId.count();
    final query = database.selectOnly(database.changes)
      ..addColumns([countExp])
      ..where(database.changes.documentId.equals(documentId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
