import 'package:drift/drift.dart';

part 'database.g.dart';

/// Table storing serialized `Change` objects.
///
/// Each row holds one change as an opaque binary blob (`Change.toBytes()`),
/// scoped to a document via [documentId].
@DataClassName('ChangeRow')
class Changes extends Table {
  /// Identifier of the document the change belongs to.
  TextColumn get documentId => text()();

  /// Identifier of the change (`change.id.toString()`).
  TextColumn get changeId => text()();

  /// The serialized change (`Change.toBytes()`).
  BlobColumn get bytes => blob()();

  @override
  Set<Column<Object>> get primaryKey => {documentId, changeId};
}

/// Table storing serialized `Snapshot` objects.
///
/// Each row holds one snapshot as an opaque binary blob
/// (`Snapshot.toBytes()`), scoped to a document via [documentId].
@DataClassName('SnapshotRow')
class Snapshots extends Table {
  /// Identifier of the document the snapshot belongs to.
  TextColumn get documentId => text()();

  /// Identifier of the snapshot (`snapshot.id`).
  TextColumn get snapshotId => text()();

  /// The serialized snapshot (`Snapshot.toBytes()`).
  BlobColumn get bytes => blob()();

  @override
  Set<Column<Object>> get primaryKey => {documentId, snapshotId};
}

/// The drift database backing the CRDT storage adapters.
///
/// It exposes the [Changes] and [Snapshots] tables. The schema is created
/// automatically on first use.
@DriftDatabase(tables: [Changes, Snapshots])
class CRDTDriftDatabase extends _$CRDTDriftDatabase {
  /// Creates a database on top of the given query [executor].
  CRDTDriftDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
