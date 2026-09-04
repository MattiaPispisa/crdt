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

/// Table storing the `PeerId` a document writes under.
///
/// One row per document: the identity is what makes a reopened document the
/// same writer it was before.
@DataClassName('PeerRow')
class Peers extends Table {
  /// Identifier of the document the identity belongs to.
  TextColumn get documentId => text()();

  /// The peer id as text (`PeerId.toString()`).
  TextColumn get peerId => text()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};
}

/// The drift database backing the CRDT storage adapters.
///
/// It exposes the [Changes], [Snapshots] and [Peers] tables. The schema is
/// created automatically on first use.
@DriftDatabase(tables: [Changes, Snapshots, Peers])
class CRDTDriftDatabase extends _$CRDTDriftDatabase {
  /// Creates a database on top of the given query [executor].
  CRDTDriftDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  /// Adds what a later schema version introduced to a database already on
  /// disk.
  ///
  /// Version 2 added [Peers]. A database written by version 1 holds changes
  /// and snapshots that stay as they are, so the upgrade only creates the new
  /// table.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(peers);
          }
        },
      );
}
