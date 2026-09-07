## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.3.0/packages/adapters/persistence/crdt_lf_sqlite)

**Date:** --

### Changed

- **A change is named by its author and its clock**, not by a string: `changes` has `author`, `hlc_l`
  and `hlc_c` in place of the one text column. It is the same name written apart, so nothing is
  stored twice — and SQL can compare it, which is what a version vector asks. The primary key
  `(document_id, author, hlc_l, hlc_c)` is already the index that comparison wants.

- **The database carries a schema version**, in `PRAGMA user_version`, and this build writes version
  2. There was none before, and `CREATE TABLE IF NOT EXISTS` never reshapes an existing table, so
  opening a `0.2.0` database rebuilds `changes` — from its old `change_id` column rather than from
  the stored bytes, so a change this build cannot decode still migrates. It runs in one savepoint,
  and every later open reads the version and returns.

- **The storages implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence), re-exported here so one
  import stays enough. Code written against a storage now runs on any adapter, and
  `CRDTDocumentPersistence` keeps a whole document on disk for you — see that package's README.

- **`CRDTSqlite` is now a `CRDTStorageBackend`.** `documentIds` is a `UNION` over the three tables,
  the `peers` one included, so a document that was created and never written to is still listed.
  `close()` is idempotent.

- **`deleteDocumentData` is now `deleteDocument`**, the name the contract uses. Same behavior: the
  changes, the snapshots and the identity, in one transaction.

- **Every storage method stays synchronous** — sqlite3 answers on the spot, and the return types say
  so. **`await` on these calls is no longer valid, drop it.**

- **A transaction no longer lets another document write inside it.** Savepoints are a stack on the
  connection, so two documents sharing one could interleave and a rollback would silently undo the
  other's writes. Each transaction now takes a name of its own, a synchronous body is carried through
  without suspending, and an asynchronous one waits for whatever is already open. A call made from
  inside a transaction still nests.

- `runInTransactionAsync` is gone. `runInTransaction` takes a `FutureOr` body and covers both.

- **`CRDTSqlitePeerIdStorage` keeps the `PeerId` a document writes under**, in a new `peers` table, so
  a restart no longer adds a peer to the version vector. Read it before building the document:
  `CRDTDocument(documentId: id, peerId: database.peerIdStorageForDocument(id).loadOrCreate())`. An
  existing database picks the table up on the next open.

- **`getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s. The database answers it: a
  change outside the range is never read and never decoded.

- `CRDTDocumentStorage` comes from `crdt_lf_persistence` and is re-exported, so the import path does
  not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- `storageForDocument` returns a `CRDTSqliteDocumentStorage`, whose `transaction()` is a real SQLite
  transaction: a prune lands whole or not at all. It is built on savepoints, so a batch that opens a
  transaction of its own nests instead of failing on a second `BEGIN`. Its `close()` does nothing —
  one file holds every document, so the connection stays `CRDTSqlite.close()`'s to release.

- Requires `crdt_lf: ^4.2.0`.

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.2.0/packages/adapters/persistence/crdt_lf_sqlite)

**Date:** 2026-08-16

- Requires `crdt_lf: ^4.0.0` instead of `>=3.0.0 <5.0.0`.

## [0.1.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.1.1/packages/crdt_lf_sqlite)

**Date:** 2026-07-28

- Widens the `crdt_lf` constraint to `>=3.0.0 <5.0.0`. No functional changes, and no migration of existing databases.

## [0.1.0+2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.1.0+2/packages/crdt_lf_sqlite)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.1.0+1/packages/crdt_lf_sqlite)

**Date:** 2026-07-18

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.1.0/packages/crdt_lf_sqlite)

### Initial Release

- Added `CRDTSqlite` utility class for opening a SQLite database and creating the CRDT schema
- Added `CRDTSqliteChangeStorage` and `CRDTSqliteSnapshotStorage` for persisting `Change` and `Snapshot` objects as binary blobs, scoped per document via an indexed `document_id` column
- Added `CRDTDocumentStorage` container bundling both storages for a document
