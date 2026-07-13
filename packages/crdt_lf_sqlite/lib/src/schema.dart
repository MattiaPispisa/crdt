/// Name of the table used to store `Change`s.
const String changesTable = 'changes';

/// Name of the table used to store `Snapshot`s.
const String snapshotsTable = 'snapshots';

/// DDL that creates the tables used by the storage classes.
///
/// Both `Change` and `Snapshot` are persisted as opaque binary blobs (via
/// their `toBytes()` methods) in a single SQLite database. Each row is scoped
/// to a document through the `document_id` column.
const String createSchemaSql = '''
CREATE TABLE IF NOT EXISTS $changesTable (
  document_id TEXT NOT NULL,
  change_id   TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, change_id)
);

CREATE TABLE IF NOT EXISTS $snapshotsTable (
  document_id TEXT NOT NULL,
  snapshot_id TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, snapshot_id)
);
''';
