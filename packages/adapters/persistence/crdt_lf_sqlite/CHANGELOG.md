## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.3.0/packages/crdt_lf_sqlite)

**Date:** --

### Changed

- **The storages now implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) package. Code written
  against a storage runs on any adapter now, and `CRDTDocumentPersistence` keeps a whole document
  on disk for you — see that package's README.

- **Every storage method returns a `Future`.** sqlite3 is synchronous and the bodies still are, so
  nothing suspends; the futures are what the shared contract needs, so that the asynchronous
  backends fit the same type. Add `await` at the call sites:
  `changes.getChanges()` is now `await changes.getChanges()`.

- `CRDTDocumentStorage` is no longer declared here. It comes from `crdt_lf_persistence` and is
  re-exported, so the import path does not change.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- Requires `crdt_lf: ^4.2.0`.

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
