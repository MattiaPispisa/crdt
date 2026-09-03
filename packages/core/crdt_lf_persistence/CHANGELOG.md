## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.0/packages/core/crdt_lf_persistence)

**Date:** --

First release.

### Added

- `CRDTChangeStorage`, `CRDTSnapshotStorage` and `CRDTDocumentStorage`: the contract every
  `crdt_lf` storage adapter keeps.
- `CRDTDocumentPersistence`: keeps a `CRDTDocument` on disk as it changes.