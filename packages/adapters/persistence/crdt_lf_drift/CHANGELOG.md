## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.3.0/packages/adapters/persistence/crdt_lf_drift)

**Date:** --

### Changed

- **The storages now implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) package. Code written
  against a storage runs on any adapter now, and `CRDTDocumentPersistence` keeps a whole document
  on disk for you — see that package's README. The contract is re-exported here, so one import is
  enough: `openPersistentDocument` reads the stored identity, builds the document and restores it
  in one call, `readDocument` gives a document to read and not follow, and `copyDocument` moves one
  to another adapter.

- **`CRDTDrift` is now a `CRDTStorageBackend`.** It answers `documentIds` with a `UNION` over the
  three tables — the `peers` one included, so a document that was created and never written to is
  still listed — and `storageForDocument`, `peerIdStorageForDocument` and `close` were already
  there under those names. `close` is now idempotent. App code written against the interface runs
  on any adapter.

- **`deleteDocumentData` is now `deleteDocument`**, which is the name the interface uses. Same
  behaviour: the changes, the snapshots and the identity, in one transaction.

- **`CRDTDriftPeerIdStorage` keeps the `PeerId` a document writes under**, in a new `peers` table.
  Without it every restart writes under a new author, and the version vector grows by one peer per
  session. Read it before building the document, with
  `database.peerIdStorageForDocument(id).loadOrCreate()`.

- **The schema is at version 2**, and the package now has a `MigrationStrategy`. The upgrade only
  creates the `peers` table; changes and snapshots written by version 1 stay as they are.

- **`getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s: what a vector has not seen,
  what it has seen, or the range between them. Filtered in Dart for now, so it narrows the result
  and not the rows read.

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
