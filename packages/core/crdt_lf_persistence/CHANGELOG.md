## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.2.0/packages/core/crdt_lf_persistence)

**Date:** 2026-10-01

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_persistence-v0.1.1+1...crdt_lf_persistence-v0.2.0)

### Added

- `keepSnapshots` on `open`, `openSync` and `openDocument`: how many snapshots stay on the disk
  (1 by default, `null` for all).
- `whenStored(version)` completes once the disk can bring back that version, changes or snapshot;
  `storedVersion` is what the disk holds now.
- `flush(throwOnError: true)` throws a failed write instead of returning.

### Changed

- `compact()` throws when the snapshot or the prune fails to write.
- Needs Dart 3.3 and `crdt_lf` 5.1.0 or later.

### Fixed

- A snapshot the document took before `open` is written; the next open lost it.
- A failed snapshot write no longer lets its prune delete the changes it covers, and is retried.
- Two concurrent `flush()` calls no longer hide a failed write from each other.
- `flush()` waits only for what was queued when it was called: with edits arriving faster than the
  writes it never returned, and neither did `dispose()` or `compact()`.
- `documentAt` throws instead of answering a version whose history was pruned with an older state.

## [0.1.1+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.1+1/packages/core/crdt_lf_persistence)

**Date:** 2026-09-27

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_persistence-v0.1.1...crdt_lf_persistence-v0.1.1+1)

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.1.1`.

## [0.1.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.1/packages/core/crdt_lf_persistence)

**Date:** 2026-09-19

Widens the `crdt_lf` constraint to `>=4.2.0 <6.0.0`, so this package resolves against
`crdt_lf` 5.0.0 as well as 4.x. No functional changes.

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.0/packages/core/crdt_lf_persistence)

**Date:** 2026-09-07

First release. The storage contract behind the `crdt_lf` persistence adapters — the
[README](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf_persistence) has the
API and the examples.

### Added

- `CRDTChangeStorage`, `CRDTSnapshotStorage`, `CRDTDocumentStorage` and `CRDTPeerIdStorage`: what
  one document has on disk. `crdt_lf_hive`, `crdt_lf_drift` and `crdt_lf_sqlite` implement them, so
  code written against the contract runs on any adapter.

- `CRDTStorageBackend`: the database itself — `storageForDocument`, `peerIdStorageForDocument`,
  `documentIds`, `deleteDocument`, `close`.

- `CRDTDocumentPersistence`: keeps a `CRDTDocument` on disk as it changes. Writes are batched, a
  failed write is retried with a growing delay (250 ms, doubling, capped at 30 s),
  `hasUnwrittenChanges` says whether anything is still waiting, and `compact()` snapshots and
  prunes on demand. `openSync` restores before it returns, on a backend whose reads are synchronous,
  so a Flutter app builds its first frame from stored state.

- On the backend, everything an app does with a stored document: `openDocument(id)` (identity,
  document and restore in one call), `readDocument(id)` for a preview or a read-only view,
  `documentAt(id, version)` for a history view, and `copyDocumentTo(other, id)` for a backup or a
  move to another adapter. The three read-and-copy calls are also on a single `CRDTDocumentStorage`.

- `CRDTChangeStorage.getChanges` takes `newerThan` and `upTo`, both `VersionVector`s;
  `filterByVersion` is the fallback for a backend that cannot ask its own query language.

- `newestSnapshot`: which snapshot to restore from when a crash left two. Settled by version vector,
  then by the smaller id, so every backend answers the same from the same bytes.

- Every storage method returns a `FutureOr`, so a backend that answers without touching the disk
  never suspends; `CRDTFutureOr.chain` works on either.

- `CRDTDocumentStorage.close()` and `transaction()`, both with a working default, so an adapter only
  fills in what its backend can do.
