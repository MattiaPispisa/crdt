## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.2.0/packages/crdt_lf_sqlite)

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
