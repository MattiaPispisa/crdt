## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.3.0/packages/crdt_lf_drift)

**Date:** --

### Changed

- **The storages now implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) package. Code written
  against a storage runs on any adapter now, and `CRDTDocumentPersistence` keeps a whole document
  on disk for you — see that package's README.

- `CRDTDocumentStorage` is no longer declared here. It comes from `crdt_lf_persistence` and is
  re-exported, so the import path does not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- Requires `crdt_lf: ^4.2.0`.

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.2.0/packages/crdt_lf_drift)

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
