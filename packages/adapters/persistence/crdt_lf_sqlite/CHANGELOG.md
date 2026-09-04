## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.3.0/packages/adapters/persistence/crdt_lf_sqlite)

**Date:** --

### Changed

- **The storages now implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) package. Code written
  against a storage runs on any adapter now, and `CRDTDocumentPersistence` keeps a whole document
  on disk for you — see that package's README.

- **Every storage method stays synchronous.** sqlite3 answers on the spot, and the return types
  say so: `getChanges()` gives a `List<Change>`, `saveChange()` gives `void`. The shared contract
  asks only for a `FutureOr`, which a plain value satisfies, so the same code still runs on the
  asynchronous backends. `await` on these calls is no longer valid — drop it.

- **A transaction no longer lets another document write inside it.** Two documents sharing one
  connection could interleave: savepoints are a stack on the connection, so a rollback undid
  every write made after it, the other document's included, and the transaction that lost the
  write never saw an error. Each transaction now takes a name of its own, a synchronous body is
  carried through without suspending, and an asynchronous one waits for whatever is already open.
  A call made from *inside* a transaction still nests, so a batch method run after an `await` is
  not deferred past the transaction it belongs to.

- `runInTransactionAsync` is gone. `runInTransaction` takes a `FutureOr` body and covers both.

- **`CRDTSqlitePeerIdStorage` keeps the `PeerId` a document writes under**, in a new `peers`
  table. Without it every restart writes under a new author, and the version vector grows by one
  peer per session. Read it before building the document:
  `CRDTDocument(documentId: id, peerId: database.peerIdStorageForDocument(id).loadOrCreate())`.
  The table is created by the same `CREATE TABLE IF NOT EXISTS` run as the other two, so an
  existing database picks it up on the next open.

- **`getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s: what a vector has not seen,
  what it has seen, or the range between them. Filtered in Dart for now, so it narrows the result
  and not the rows read.

- `deleteDocumentData` now removes the stored identity too, and does its deletes in one
  transaction.

- `CRDTDocumentStorage` is no longer declared here. It comes from `crdt_lf_persistence` and is
  re-exported, so the import path does not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- `storageForDocument` now returns a `CRDTSqliteDocumentStorage`, which backs the contract's
  `transaction()` with a real SQLite transaction: a prune either lands whole or not at all. It is
  built on savepoints, so a batch that opens a transaction of its own nests inside instead of
  failing on a second `BEGIN`. Its `close()` does nothing — one database file holds every document,
  so the connection stays `CRDTSqlite.close()`'s to release.

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
