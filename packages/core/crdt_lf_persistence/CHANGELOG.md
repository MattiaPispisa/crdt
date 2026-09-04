## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_persistence-v0.1.0/packages/core/crdt_lf_persistence)

**Date:** --

First release.

### Added

- `CRDTChangeStorage`, `CRDTSnapshotStorage` and `CRDTDocumentStorage`: the contract every
  `crdt_lf` storage adapter keeps for **one** document.

- `CRDTStorageBackend`: the contract for the database itself — `storageForDocument`,
  `peerIdStorageForDocument`, `documentIds`, `deleteDocument`, `close`. An app has notes, not a
  note, and a `CRDTDocumentStorage` knows nothing about the documents next to it. Code written
  against this runs on any adapter, so changing backend changes only the line that opens it.
  `crdt_lf_hive`, `crdt_lf_drift` and `crdt_lf_sqlite` all implement it.
- `CRDTDocumentPersistence`: keeps a `CRDTDocument` on disk as it changes. A write that fails keeps
  what it carried and arms a retry, waiting longer after each failure in a row (250 ms, doubling,
  capped at 30 s), so a document that goes quiet after a failure still reaches the disk;
  `hasUnwrittenChanges` says whether anything is still waiting, and `flush()` gives up for the round
  instead of retrying a storage that just refused it.
- `CRDTPeerIdStorage`: the `PeerId` a document writes under, kept so a reopened document is the
  same author it was before. Without it `CRDTDocument` mints a new id per restart, and the version
  vector gains an entry that never leaves. It stands apart from `CRDTDocumentStorage` because it
  is needed earlier — the id has to exist before the document — so an app that stores no changes
  and no snapshots can still use it. `loadOrCreate()` is the read-or-mint step, and `loadOr(author)`
  is the same with a seed for a document that has no identity yet — a stored id always wins.

- `CRDTStorageBackendDocuments`, the extension that puts everything an app does on the backend
  itself — so it is all one dot away, like the `loadOrCreate` and `getLatestSnapshot` this package
  already had:

  - `openDocument(id)`: the steps of opening a stored document, in the order they have to happen.
    Read the stored `PeerId` — it has to exist before the document, so
    `CRDTDocumentPersistence.open` cannot do it — build the `CRDTDocument`, restore. It hands back
    both the document and the persistence, and disposes the document if the restore fails, so a
    caller never gets half of one. Build the handlers on the document it returns; connect a sync
    client after it, never before.
  - `readDocument(id)`, for everything that reads and does not write back — a preview in a list of
    notes, a read-only view, an export. Nothing follows what it hands back, and on a synchronous
    backend it returns without suspending, so a list of fifty notes is built inside one frame.
  - `documentAt(id, version)`: the document as it stood at a version, which is what a history view
    reads. It is the consumer `CRDTChangeStorage.getChanges(upTo:)` was for. How far back it
    reaches is what the log still holds, and it says so by throwing rather than handing back a
    document that is quietly short.
  - `copyDocumentTo(other, id)`: a whole document to another backend, identity included — a backup,
    a restore, or a move to another adapter.

- `CRDTDocumentStorageReading`: `readDocument()`, `documentAt(version)` and `copyTo(other)` on a
  single `CRDTDocumentStorage`, for when that is all you hold. `copyTo` also takes the storage of a
  **different** document, which is how a document is duplicated — leave the identities out there,
  since two documents writing under one `PeerId` can mint the same operation id twice.

- `CRDTDocumentPersistence.compact()`: what `compactAfter` does on its own, on demand — a "save and
  compact" button, or the moment an app goes to the background. It waits for the snapshot and the
  prune to reach the disk.

- `CRDTPeerIdStorage.loadOr(author)`: the stored id, or `author`, saved before it is returned. The
  stored one always wins.

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