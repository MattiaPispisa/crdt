## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.3.0/packages/adapters/persistence/crdt_lf_drift)

**Date:** 2026-09-07

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_drift-v0.2.0...crdt_lf_drift-v0.3.0)

### Changed

- **A change is named by its author and its clock**, not by a string: `changes` has `author`, `hlcL`
  and `hlcC` in place of the one text column. It is the same name written apart, so nothing is
  stored twice — and SQL can compare it, which is what a version vector asks. The clock takes two
  columns to stay inside the 53 bits JavaScript keeps exactly, since this adapter runs on the web.

- **The schema is at version 2**, and the package has a `MigrationStrategy`. A database written by
  `0.2.0` gains the `peers` table, and `changes` is rebuilt from its old `change_id` column rather
  than from the stored bytes — so a change this build cannot decode still migrates. Snapshots stay
  as they are.

- **The storages implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence), re-exported here so one
  import stays enough. Code written against a storage now runs on any adapter, and
  `CRDTDocumentPersistence` keeps a whole document on disk for you — see that package's README.

- **`CRDTDrift` is now a `CRDTStorageBackend`.** `documentIds` is a `UNION` over the three tables,
  the `peers` one included, so a document that was created and never written to is still listed.
  `close` is now idempotent.

- **`deleteDocumentData` is now `deleteDocument`**, the name the contract uses. Same behavior: the
  changes, the snapshots and the identity, in one transaction.

- **`CRDTDriftPeerIdStorage` keeps the `PeerId` a document writes under**, in a new `peers` table, so
  a restart no longer adds a peer to the version vector. Read it before building the document, with
  `database.peerIdStorageForDocument(id).loadOrCreate()`.

- **`getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s. The database answers it: a
  change outside the range is never read and never decoded.

- Storage methods are declared `FutureOr` by the contract. drift is asynchronous end to end, so every
  method here still returns a `Future` and call sites do not change. `transaction` now accepts a
  `FutureOr` body.

- `CRDTDocumentStorage` comes from `crdt_lf_persistence` and is re-exported, so the import path does
  not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- `storageForDocument` returns a `CRDTDriftDocumentStorage`, whose `transaction()` is a real drift
  transaction: a prune lands whole or not at all. Its `close()` does nothing — one file holds every
  document, so the connection stays `CRDTDrift.close()`'s to release.

- Requires `crdt_lf: ^4.2.0`.

### Fixed

- **A delete of very many changes no longer fails.** `deleteChanges` built one `IN (?, ?, …)` with a
  variable per id, and SQLite refuses more than `SQLITE_MAX_VARIABLE_NUMBER` of them — which a long
  running document reached, since a prune hands over everything it removed at once. Deletes now go
  through a batch, one hit on the primary key each. `deleteSnapshots` cuts its ids into pieces
  instead, a snapshot id being an opaque string rather than a key the table is ordered by.

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
