import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:drift/drift.dart';

/// Storage utility for managing [Change] objects in a drift database.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects. All rows are scoped to a single document via
/// the [documentId] column, so several documents can share the same database.
class CRDTDriftChangeStorage {
  /// Creates a new [CRDTDriftChangeStorage] instance.
  ///
  /// [database] is the drift database used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier for the document these changes
  /// belong to.
  CRDTDriftChangeStorage(this.database, this.documentId);

  /// The drift database used for storing [Change] objects.
  final CRDTDriftDatabase database;

  /// The unique identifier for the document these changes belong to.
  final String documentId;

  ChangesCompanion _companion(Change change) {
    return ChangesCompanion.insert(
      documentId: documentId,
      changeId: change.id.toString(),
      bytes: change.toBytes(),
    );
  }

  /// Saves a [Change] to the storage.
  ///
  /// If a change with the same id already exists it is overwritten.
  Future<void> saveChange(Change change) {
    return database
        .into(database.changes)
        .insertOnConflictUpdate(_companion(change));
  }

  /// Saves multiple [Change] objects to the storage.
  ///
  /// This method is more efficient than calling [saveChange] multiple times
  /// as it performs a single batch.
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

  /// Retrieves all [Change] objects from the storage for this document.
  Future<List<Change>> getChanges() async {
    final query = database.select(database.changes)
      ..where((row) => row.documentId.equals(documentId));
    final rows = await query.get();
    return rows.map((row) => Change.fromBytes(row.bytes)).toList();
  }

  /// Deletes a [Change].
  ///
  /// Returns true if the change was found and deleted, false otherwise.
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

  /// Deletes multiple [Change] objects.
  ///
  /// Returns the number of changes that were actually deleted.
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

  /// Clears all [Change] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() async {
    await (database.delete(database.changes)
          ..where((row) => row.documentId.equals(documentId)))
        .go();
  }

  /// Returns the number of [Change] objects for this document in the storage.
  Future<int> get count async {
    final countExp = database.changes.changeId.count();
    final query = database.selectOnly(database.changes)
      ..addColumns([countExp])
      ..where(database.changes.documentId.equals(documentId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Returns true if the storage is empty for this document.
  Future<bool> get isEmpty async => (await count) == 0;

  /// Returns true if the storage is not empty for this document.
  Future<bool> get isNotEmpty async => (await count) > 0;
}
