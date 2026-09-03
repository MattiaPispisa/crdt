## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.0/packages/core/crdt_lf_persistence)

**Date:** --

First release.

### Added

- `CRDTChangeStorage`, `CRDTSnapshotStorage` and `CRDTDocumentStorage`: the contract every
  `crdt_lf` storage adapter keeps. Until now each adapter declared its own `CRDTDocumentStorage`,
  so code written for one backend did not run on another.

- `CRDTDocumentPersistence`: keeps a `CRDTDocument` on disk as it changes. It reads the document
  back on `open`, then follows `CRDTDocument.events` and writes down what each event reports —
  the document is never exported again. It batches writes behind a short delay, replaces the old
  snapshot only after the new one is stored, and follows a prune by deleting what left the store
  and writing the survivors again.

- `InMemoryDocumentStorage`, for tests.

- `FileDocumentStorage` (in `package:crdt_lf_persistence/io.dart`): one document, one plain file,
  no database. The whole file is rewritten through a temporary file, so a process killed
  mid-write leaves the previous file intact. The file carries a format version and a document id.
