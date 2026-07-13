## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_sqlite-v0.1.0/packages/crdt_lf_sqlite)

### Initial Release

- Added `CRDTSqlite` utility class for opening a SQLite database and creating the CRDT schema
- Added `CRDTSqliteChangeStorage` and `CRDTSqliteSnapshotStorage` for persisting `Change` and `Snapshot` objects as binary blobs, scoped per document via an indexed `document_id` column
- Added `CRDTDocumentStorage` container bundling both storages for a document
