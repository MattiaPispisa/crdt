import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';

part 'database.g.dart';

// The column getters below are read by the drift generator, not by the
// running program: the generated `$ChangesTable` and friends override them
// with the real `GeneratedColumn`s. Nothing ever calls these bodies, so
// coverage counts them as dead lines forever.
// coverage:ignore-start

/// Table storing serialized `Change` objects.
///
/// Each row holds one change as an opaque binary blob (`Change.toBytes()`),
/// scoped to a document via [documentId].
///
/// A change is named by [author] and its clock rather than by the string
/// `change.id.toString()` would give. It is the same name written apart: an
/// `OperationId` **is** a peer and a clock. Kept apart, SQL can compare it —
/// which is what a version vector asks — and the primary key is already the
/// index that comparison wants.
@DataClassName('ChangeRow')
class Changes extends Table {
  /// Identifier of the document the change belongs to.
  TextColumn get documentId => text()();

  /// The peer that wrote the change (`change.author.toString()`).
  TextColumn get author => text()();

  /// The logical time of the change (`change.hlc.l`).
  ///
  /// The clock is two columns because `l` is 48 bits and `c` is 16: together
  /// they pass the 53 bits an integer keeps exactly in JavaScript, and this
  /// adapter runs on the web.
  IntColumn get hlcL => integer()();

  /// The counter of the change (`change.hlc.c`).
  IntColumn get hlcC => integer()();

  /// The serialized change (`Change.toBytes()`).
  BlobColumn get bytes => blob()();

  @override
  Set<Column<Object>> get primaryKey => {documentId, author, hlcL, hlcC};
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

// coverage:ignore-end

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

  /// Adds what version 2 introduced to a database written by version 1.
  ///
  /// Version 1 had no [Peers] table, and named a change with one text column
  /// holding `change.id.toString()`. Version 2 creates the table and splits
  /// that name into [Changes.author], [Changes.hlcL] and [Changes.hlcC].
  ///
  /// The split reads the old column, not the stored bytes: a change whose blob
  /// this build cannot decode still migrates.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(peers);
            await _splitChangeIds(m);
          }
        },
      );

  /// Rebuilds [Changes] with the name of a change written apart.
  ///
  /// SQLite cannot change a primary key in place, so the old table is set
  /// aside, the new one is created, and the rows move across one by one.
  Future<void> _splitChangeIds(Migrator m) async {
    await customStatement('ALTER TABLE changes RENAME TO changes_v1');
    await m.createTable(changes);

    final rows = await customSelect(
      'SELECT document_id, change_id, bytes FROM changes_v1',
    ).get();

    if (rows.isNotEmpty) {
      await batch((batch) {
        for (final row in rows) {
          final id = OperationId.parse(row.read<String>('change_id'));
          batch.insert(
            changes,
            ChangesCompanion.insert(
              documentId: row.read<String>('document_id'),
              author: id.peerId.toString(),
              hlcL: id.hlc.l,
              hlcC: id.hlc.c,
              bytes: row.read<Uint8List>('bytes'),
            ),
          );
        }
      });
    }

    await customStatement('DROP TABLE changes_v1');
  }
}
