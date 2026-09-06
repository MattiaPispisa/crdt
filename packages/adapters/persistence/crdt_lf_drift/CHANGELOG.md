## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.3.0/packages/adapters/persistence/crdt_lf_drift)

**Date:** --

### Changed

- **A change is named by its author and its clock**, not by a string. `changes` names a change by
  `author`, `hlcL` and `hlcC` instead of by the one text column `change.id.toString()` used to
  fill. It is the same name written apart — an `OperationId` **is** a peer and a clock — so
  nothing is stored twice. Kept apart, SQL can compare it, which is what a version vector asks,
  and the primary key `(documentId, author, hlcL, hlcC)` is already the index that comparison
  wants. The clock takes two columns because `l` is 48 bits and `c` is 16: together they stay
  inside the 53 bits an integer keeps exactly in JavaScript, and this adapter runs on the web.

- **The schema is at version 2**, and the package now has a `MigrationStrategy`. A database
  written by `0.2.0` is at version 1: it gains the `peers` table, and `changes` is rebuilt into
  its new shape. The rebuild reads the old `change_id` column, not the stored bytes, so a change
  whose blob this build cannot decode still migrates. Snapshots stay as they are.

- **The storages now implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) package. Code written
  against a storage runs on any adapter now, and `CRDTDocumentPersistence` keeps a whole document
  on disk for you — see that package's README. The contract is re-exported here, so one import is
  enough: `openDocument` reads the stored identity, builds the document and restores it in one
  call, `readDocument` gives a document to read and not follow, and `copyDocumentTo` moves one to
  another adapter.

- **`CRDTDrift` is now a `CRDTStorageBackend`.** It answers `documentIds` with a `UNION` over the
  three tables — the `peers` one included, so a document that was created and never written to is
  still listed — and `storageForDocument`, `peerIdStorageForDocument` and `close` were already
  there under those names. `close` is now idempotent. App code written against the interface runs
  on any adapter.

- **`deleteDocumentData` is now `deleteDocument`**, which is the name the interface uses. Same
  behavior: the changes, the snapshots and the identity, in one transaction.

- **`CRDTDriftPeerIdStorage` keeps the `PeerId` a document writes under**, in a new `peers` table.
  Without it every restart writes under a new author, and the version vector grows by one peer per
  session. Read it before building the document, with
  `database.peerIdStorageForDocument(id).loadOrCreate()`.

- **`getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s: what a vector has not seen,
  what it has seen, or the range between them. The database answers it: a change outside the range
  is never read and never decoded, which is the cost of asking a long history what is new.

- **Storage methods are declared `FutureOr` by the shared contract.** drift is asynchronous end to
  end, so every method here still returns a `Future` and call sites do not change. `transaction`
  now accepts a `FutureOr` body, which it wraps.

- `deleteDocument` now removes the stored identity too, and does its deletes in one
  transaction.

- `CRDTDocumentStorage` is no longer declared here. It comes from `crdt_lf_persistence` and is
  re-exported, so the import path does not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- `storageForDocument` now returns a `CRDTDriftDocumentStorage`, which backs the contract's
  `transaction()` with `database.transaction(...)`: a prune either lands whole or not at all. Its
  `close()` does nothing — one database file holds every document, so the connection stays
  `CRDTDrift.close()`'s to release.

- Requires `crdt_lf: ^4.2.0`.

### Fixed

- **A delete of very many changes no longer fails.** `deleteChanges` built a single
  `IN (?, ?, …)` with one variable per id, and SQLite refuses a statement that binds more than
  `SQLITE_MAX_VARIABLE_NUMBER` of them — 32766 on a current build, 999 on an older one. A prune
  hands over everything it removed at once, and compaction is off by default, so a document that
  ran for a long time reached it. Deletes now go through a batch, one hit on the primary key each,
  which has no such ceiling. `deleteSnapshots` still names its ids in one statement — a snapshot
  id is an opaque string, not a key the table is ordered by — so it cuts them into pieces instead.

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.2.0/packages/adapters/persistence/crdt_lf_drift)

**Date:** 2026-08-16

- Requires `crdt_lf: ^4.0.0` instead of `>=3.0.0 <5.0.0`.

## [0.1.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.1/packages/crdt_lf_drift)

**Date:** 2026-07-28

- Widens the `crdt_lf` constraint to `>=3.0.0 <5.0.0`. No functional changes, and no migration of existing databases.

## [0.1.0+2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.0+2/packages/crdt_lf_drift)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.0+1/packages/crdt_lf_drift)

**Date:** 2026-07-18

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.0/packages/crdt_lf_drift)

### Initial Release

- Added `CRDTDrift` utility class for opening a drift database (file or in-memory)
- Added `CRDTDriftDatabase` with `changes` and `snapshots` tables
- Added `CRDTDriftChangeStorage` and `CRDTDriftSnapshotStorage` for persisting `Change` and `Snapshot` objects as binary blobs, scoped per document via the `document_id` column
- Added `CRDTDocumentStorage` container bundling both storages for a document
