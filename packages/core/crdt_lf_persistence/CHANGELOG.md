## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.0/packages/core/crdt_lf_persistence)

**Date:** --

First release.

### Added

- `CRDTChangeStorage`, `CRDTSnapshotStorage` and `CRDTDocumentStorage`: the contract every
  `crdt_lf` storage adapter keeps.
- `CRDTDocumentPersistence`: keeps a `CRDTDocument` on disk as it changes. A write that fails keeps
  what it carried, so the next `flush()` tries the batch again; `hasUnwrittenChanges` says whether
  anything is still waiting, and `flush()` gives up for the round instead of retrying a storage that
  just refused it.
- `CRDTPeerIdStorage`: the `PeerId` a document writes under, kept so a reopened document is the
  same author it was before. Without it `CRDTDocument` mints a new id per restart, and the version
  vector gains an entry that never leaves. It stands apart from `CRDTDocumentStorage` because it
  is needed earlier — the id has to exist before the document — so an app that stores no changes
  and no snapshots can still use it. `loadOrCreate()` is the read-or-mint step.

- **Every storage method returns a `FutureOr`.** A backend that answers without touching the disk
  returns the value itself and narrows its return type to say so; an asynchronous backend returns
  a `Future`. `CRDTFutureOr.chain` is how a caller works on either without an `await` that would
  suspend a backend that never needed to.

- `CRDTDocumentPersistence.openSync`: the `open` a storage with synchronous reads allows. The
  document is restored before it returns, so a Flutter app builds its first frame from stored
  state. It throws a `StateError` on a backend whose reads return a `Future`.

- **`CRDTChangeStorage.getChanges` takes `newerThan` and `upTo`**, both `VersionVector`s: what a
  vector has not seen, what it has seen, or the range between them. `filterByVersion` is the
  meaning of both bounds, and the fallback for a backend that cannot ask its own query language.
  It uses the same test as `CRDTDocument.exportChangesNewerThan`.

- A snapshot write now goes in one `transaction()` as well: it reads what is stored, writes the
  new snapshot, then drops the old one. `transaction` also gained a rule — a body that returns
  without suspending must be carried through without suspending, or on a backend with one shared
  connection another document can write inside the transaction and lose that write to a rollback.

- `CRDTDocumentStorage.close()` and `CRDTDocumentStorage.transaction()`. Both come with a working
  default — do nothing, and run the body — so an adapter only fills in what its backend can do.
  A prune now drops the covered changes and rewrites the survivors inside one `transaction()`.

- `newestSnapshot(List<Snapshot>)` and `CRDTSnapshotStorage.getLatestSnapshot()`: which of the
  stored snapshots to restore from. The answer comes from the version vector, never from the order
  a backend returns its rows in. `CRDTDocumentPersistence` restores through the same function, so
  a caller reading the snapshot itself and the restore never disagree.

- **A change pruned before it was ever written no longer comes back.** A snapshot taken while
  changes were still queued deleted them from a store they had not reached yet, and the queue then
  wrote them down. No later prune would ever name them again — a prune only reports what the
  document still holds — so they sat on the disk for the life of the store, and compaction did not
  shrink it. The queue now takes the prune too: removed changes leave it, and a survivor's old
  bytes are replaced by the rewritten ones.