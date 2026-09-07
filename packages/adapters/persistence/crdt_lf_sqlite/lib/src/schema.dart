import 'package:crdt_lf/crdt_lf.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Name of the table used to store `Change`s.
const String changesTable = 'changes';

/// Name of the table used to store `Snapshot`s.
const String snapshotsTable = 'snapshots';

/// Name of the table used to store the `PeerId` a document writes under.
const String peersTable = 'peers';

/// The schema this build writes, kept in `PRAGMA user_version`.
///
/// Version 1 never wrote it down — there was no version then — so a database
/// that reads back 0 is a database from version 1.
const int schemaVersion = 2;

/// Where the version 1 [changesTable] is set aside while it is rebuilt.
const String _legacyChangesTable = '${changesTable}_v1';

/// DDL that creates the tables used by the storage classes.
///
/// Both `Change` and `Snapshot` are persisted as opaque binary blobs (via
/// their `toBytes()` methods) in a single SQLite database. Each row is scoped
/// to a document through the `document_id` column.
///
/// A change is named by `author` and its clock rather than by the string
/// `change.id.toString()` would give. It is the same name written apart: an
/// `OperationId` **is** a peer and a clock. Kept apart, SQL can compare it —
/// which is what a version vector asks — and the primary key is already the
/// index that comparison wants. The clock is two columns because `l` is 48
/// bits and `c` is 16: together they pass the 53 bits an integer keeps
/// exactly in JavaScript.
const String createSchemaSql = '''
CREATE TABLE IF NOT EXISTS $changesTable (
  document_id TEXT    NOT NULL,
  author      TEXT    NOT NULL,
  hlc_l       INTEGER NOT NULL,
  hlc_c       INTEGER NOT NULL,
  bytes       BLOB    NOT NULL,
  PRIMARY KEY (document_id, author, hlc_l, hlc_c)
);

CREATE TABLE IF NOT EXISTS $snapshotsTable (
  document_id TEXT NOT NULL,
  snapshot_id TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, snapshot_id)
);

CREATE TABLE IF NOT EXISTS $peersTable (
  document_id TEXT NOT NULL,
  peer_id     TEXT NOT NULL,
  PRIMARY KEY (document_id)
);
''';

/// Creates what [database] is missing, and brings what it has up to
/// [schemaVersion].
///
/// Version 1 had no [peersTable], and named a change with one text column
/// holding `change.id.toString()`. `CREATE TABLE IF NOT EXISTS` gives it the
/// missing table but never a different shape, so [changesTable] is rebuilt:
/// SQLite cannot change a primary key in place.
///
/// The split reads the old column, not the stored bytes, so a change whose
/// blob this build cannot decode still migrates. All of it in one savepoint —
/// half a rebuilt table is worse than none.
///
/// Returns without touching the database once [schemaVersion] is written
/// down, which is every open after the first.
void createOrUpgradeSchema(sq.Database database) {
  // Nothing to do, and nothing to check: the version says the tables are
  // there in the shape this build expects.
  if (_userVersion(database) >= schemaVersion) {
    return;
  }

  _run(database, () {
    final fromVersionOne = _hasColumn(database, changesTable, 'change_id');
    if (fromVersionOne) {
      database.execute(
        'ALTER TABLE $changesTable RENAME TO $_legacyChangesTable',
      );
    }

    database.execute(createSchemaSql);

    if (fromVersionOne) {
      _copyLegacyChanges(database);
      database.execute('DROP TABLE $_legacyChangesTable');
    }

    database.execute('PRAGMA user_version = $schemaVersion');
  });
}

/// Moves the version 1 rows into the rebuilt [changesTable].
void _copyLegacyChanges(sq.Database database) {
  final rows = database.select(
    'SELECT document_id, change_id, bytes FROM $_legacyChangesTable',
  );
  if (rows.isEmpty) {
    return;
  }

  final statement = database.prepare(
    'INSERT OR REPLACE INTO $changesTable '
    '(document_id, author, hlc_l, hlc_c, bytes) VALUES (?, ?, ?, ?, ?)',
  );
  try {
    for (final row in rows) {
      final id = OperationId.parse(row['change_id'] as String);
      statement.execute([
        row['document_id'],
        id.peerId.toString(),
        id.hlc.l,
        id.hlc.c,
        row['bytes'],
      ]);
    }
  } finally {
    statement.close();
  }
}

int _userVersion(sq.Database database) {
  final result = database.select('PRAGMA user_version');
  return result.first.values.first! as int;
}

bool _hasColumn(sq.Database database, String table, String column) {
  final result = database.select('PRAGMA table_info($table)');
  return result.any((row) => row['name'] == column);
}

/// Runs [body] in a savepoint, so a half-filled table never survives.
///
/// A savepoint and not `BEGIN`: the caller may have handed over a connection
/// with a transaction already open.
void _run(sq.Database database, void Function() body) {
  const savepoint = 'crdt_lf_upgrade';
  database.execute('SAVEPOINT $savepoint');
  try {
    body();
    database.execute('RELEASE $savepoint');
  } catch (_) {
    database
      ..execute('ROLLBACK TO $savepoint')
      ..execute('RELEASE $savepoint');
    rethrow;
  }
}
