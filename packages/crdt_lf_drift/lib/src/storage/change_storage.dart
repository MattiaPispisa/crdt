import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/changes_table.dart';

/// Storage utility for managing [Change] objects in Drift.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects in a Drift database.
class CRDTChangeStorage {
  /// Creates a new [CRDTChangeStorage] instance.
  ///
  /// [database] is the Drift database that will be used to store [Change] objects.
  /// [documentId] is the unique identifier for the document these changes belong to.
  CRDTChangeStorage(this.database, this.documentId);

  /// The Drift database used for storing [Change] objects.
  final CRDTDatabase database;

  /// The unique identifier for the document these changes belong to.
  final String documentId;

  /// Generates a key for storing changes.
  String _getChangeKey(Change change) => change.id.toString();

  /// Converts a [Change] to a [ChangesCompanion] for database insertion.
  ChangesCompanion _changeToCompanion(Change change) {
    return ChangesCompanion.insert(
      id: _getChangeKey(change),
      documentId: documentId,
      operationId: change.id,
      hlc: change.hlc,
      author: change.author,
      dependencies: json.encode(change.deps.map((e) => e.toString()).toList()),
      payload: json.encode(change.payload),
    );
  }

  /// Converts a [ChangeEntity] from database to a [Change].
  Change _entityToChange(ChangeEntity entity) {
    final depsData = json.decode(entity.dependencies) as List<dynamic>;
    final deps = depsData.map((e) => OperationId.parse(e as String)).toSet();
    final payload = json.decode(entity.payload) as Map<String, dynamic>;

    return Change.fromPayload(
      id: entity.operationId,
      deps: deps,
      hlc: entity.hlc,
      author: entity.author,
      payload: payload,
    );
  }

  /// Saves a [Change] to the storage.
  Future<void> saveChange(Change change) {
    return database.into(database.changes).insert(_changeToCompanion(change));
  }

  /// Saves multiple [Change] objects to the storage.
  ///
  /// This method is more efficient than calling [saveChange] multiple times
  /// as it performs batch operations.
  Future<void> saveChanges(List<Change> changes) {
    return database.batch((batch) {
      for (final change in changes) {
        batch.insert(database.changes, _changeToCompanion(change));
      }
    });
  }

  /// Retrieves all [Change] objects from the storage for this document.
  Future<List<Change>> getChanges() async {
    final query = database.select(database.changes)
      ..where((tbl) => tbl.documentId.equals(documentId))
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]);

    final entities = await query.get();
    return entities.map(_entityToChange).toList();
  }

  /// Deletes a [Change] by its object.
  Future<bool> deleteChange(Change change) async {
    final key = _getChangeKey(change);
    final deletedRows = await (database.delete(database.changes)
          ..where((tbl) => tbl.id.equals(key) & tbl.documentId.equals(documentId)))
        .go();
    return deletedRows > 0;
  }

  /// Deletes multiple [Change] objects by their objects.
  Future<int> deleteChanges(List<Change> changes) async {
    final keys = changes.map(_getChangeKey).toList();
    return await (database.delete(database.changes)
          ..where((tbl) => tbl.id.isIn(keys) & tbl.documentId.equals(documentId)))
        .go();
  }

  /// Clears all [Change] objects for this document from the storage.
  Future<void> clear() async {
    await (database.delete(database.changes)
          ..where((tbl) => tbl.documentId.equals(documentId)))
        .go();
  }

  /// Returns the number of [Change] objects for this document in the storage.
  Future<int> get count async {
    final query = database.selectOnly(database.changes)
      ..addColumns([database.changes.id.count()])
      ..where(database.changes.documentId.equals(documentId));

    final result = await query.getSingle();
    return result.read(database.changes.id.count()) ?? 0;
  }

  /// Returns true if the storage is empty for this document.
  Future<bool> get isEmpty async => (await count) == 0;

  /// Returns true if the storage is not empty for this document.
  Future<bool> get isNotEmpty async => (await count) > 0;

  /// Stream of changes for this document.
  Stream<List<Change>> watchChanges() {
    final query = database.select(database.changes)
      ..where((tbl) => tbl.documentId.equals(documentId))
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]);

    return query.watch().map((entities) => entities.map(_entityToChange).toList());
  }
} 