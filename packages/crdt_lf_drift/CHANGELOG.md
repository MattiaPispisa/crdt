## [0.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.0+1/packages/crdt_lf_drift)

**Date:** 2026-07-18

Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_drift-v0.1.0/packages/crdt_lf_drift)

### Initial Release

- Added `CRDTDrift` utility class for opening a drift database (file or in-memory)
- Added `CRDTDriftDatabase` with `changes` and `snapshots` tables
- Added `CRDTDriftChangeStorage` and `CRDTDriftSnapshotStorage` for persisting `Change` and `Snapshot` objects as binary blobs, scoped per document via the `document_id` column
- Added `CRDTDocumentStorage` container bundling both storages for a document
