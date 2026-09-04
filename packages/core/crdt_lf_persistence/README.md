# crdt_lf_persistence

The storage contract behind the [`crdt_lf`](https://pub.dev/packages/crdt_lf)
persistence adapters, and the consumer that keeps a document on disk as it
changes.

> **Do not put this package in your `pubspec.yaml`.**
> It holds no store of its own. Pick an adapter —
> [`crdt_lf_hive`](https://pub.dev/packages/crdt_lf_hive),
> [`crdt_lf_drift`](https://pub.dev/packages/crdt_lf_drift) or
> [`crdt_lf_sqlite`](https://pub.dev/packages/crdt_lf_sqlite) — and it gives
> you `CRDTDocumentPersistence`, `CRDTDocumentStorage`, `CRDTChangeStorage`
> and `CRDTSnapshotStorage` through its own barrel. This page is the contract
> those adapters keep, and the place to read before writing a fourth one.

Three levels live here, smallest first:

- **`CRDTChangeStorage` / `CRDTSnapshotStorage` / `CRDTPeerIdStorage`** — what
  one document has on disk. `CRDTDocumentStorage` bundles the first two.
- **`CRDTStorageBackend`** — the whole database: the documents it holds, and
  the storages of each one. `crdt_lf_hive`, `crdt_lf_drift` and
  `crdt_lf_sqlite` all implement it, so an app can change backend without
  changing anything but the line that opens it.
- **`CRDTDocumentPersistence`** — the part you would otherwise write yourself:
  read the document back, then follow it and write down what moves.

And the functions that use them, so you never write these either:

All of them are **methods on the backend**, so you find them by typing a dot:

| you want to | call |
| --- | --- |
| open a document that is going to be edited | `backend.openDocument(id)` |
| read one without following it (a preview, a list) | `backend.readDocument(id)` |
| see it as it was at some version | `backend.documentAt(id, version)` |
| back it up, or move it to another adapter | `backend.copyDocumentTo(other, id)` |
| stop the log from growing, now | `persistence.compact()` |

The last three are also on a single `CRDTDocumentStorage` — `storage.readDocument()`,
`storage.documentAt(version)`, `storage.copyTo(other)` — for when that is all
you hold.

## Local only

No server to talk to: an adapter, and one call. One import, the adapter's.

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

final backend = CRDTSqlite.open('note.db');

// Reads the database into a document, then follows it.
final note = await backend.openDocument('note');
final text = CRDTFugueTextHandler(note.document, 'body');

text.insert(0, 'Hello 🌍');

await note.persistence.dispose(); // writes what is still waiting
backend.close();
```

Run it again and the text is there.
[`crdt_lf_sqlite`'s example](https://github.com/MattiaPispisa/crdt/blob/main/packages/adapters/persistence/crdt_lf_sqlite/example/main.dart)
is that, runnable.

[`example/main.dart`](example/main.dart) here takes the other side: it keeps
the contract in a map, so you can read what an adapter has to fill in.

## Offline-first, with sync

Same call, plus one rule: **open the document before you connect.**

```dart
final room = await backend.openDocument(roomId);

// Only now.
await client.connect();
```

The order is what makes the client offline-first. The restored document is what
the sync client reconciles against, so what you wrote on a plane reaches the
server after the restart. Connect first and the client catches up from the
server before it knows what it already had.

## How it works

The document reports every move of its durable state on
[`CRDTDocument.events`](https://pub.dev/documentation/crdt_lf/latest/):

| event | what the persistence does |
| --- | --- |
| `DocumentChangesApplied` | appends the changes |
| `DocumentSnapshotUpdated` | stores the snapshot, then drops the old one |
| `DocumentHistoryPruned` | deletes what left the store, writes the survivors again |

Both sources of a change are saved: what this peer wrote, and what it took in
from a peer. Reopening offline has to bring back the whole document, not half
of it.

Writes are batched behind `writeDelay` (250 ms by default). One keystroke is
one transaction, so writing on every event would put a round-trip to the disk
between the typist and the next character.

## Reading part of the log

`getChanges()` gives the whole log. Two bounds narrow it, and both take a
`VersionVector`:

| argument | keeps | for |
| --- | --- | --- |
| `newerThan` | what the vector has **not** seen | catching a peer up |
| `upTo` | what the vector **has** seen | the document as it was then |

```dart
// Everything the peer is missing.
final missing = await storage.changes.getChanges(newerThan: theirVersion);

// The document as it stood at that version.
final past = await storage.changes.getChanges(upTo: oldVersion);
```

Both use the same test as `CRDTDocument.exportChangesNewerThan`, so a storage
and a document never disagree about what a version vector covers. Passing both
keeps what sits between them.

A prune deletes the changes a snapshot covers, so `upTo` can only rebuild a
version the log still reaches back to.

## Synchronous backends

Every storage method returns a `FutureOr`. A backend that answers without
touching the disk — sqlite, or a Hive box already in memory — returns the
value itself and narrows its return type to say so:

```dart
List<Change> getChanges({VersionVector? newerThan, VersionVector? upTo});
```

Where that holds for the reads, `openSync` restores the document before it
returns, so a Flutter app builds its first frame from stored state instead of
an empty document:

```dart
final document = CRDTDocument(documentId: documentId);
final persistence = CRDTDocumentPersistence.openSync(
  document,
  database.storageForDocument(documentId),
);
// already full here
```

It throws a `StateError` on a backend whose reads return a `Future` — drift is
always one of them. Use `open` there.

Writes stay asynchronous everywhere, and so does `flush()`: they are batched
behind `writeDelay` anyway.

## When a write fails

A write that fails keeps what it carried. The changes stay queued and the whole
batch is written again — saving a change twice replaces it, so a write that half
landed costs nothing.

Trying again is not something you have to arrange. A failure arms a retry, and
each failure in a row waits longer than the one before it: 250 ms, doubling, up
to 30 s. Without that, a document that goes quiet right after a failure would
keep its changes in memory and nowhere else.

That matters more than losing one edit: the changes after a dropped one name it
as a dependency, so a reload would replay them against something the document
cannot resolve.

```dart
final persistence = await CRDTDocumentPersistence.open(
  document,
  storage,
  onError: (error, stack) => log(error), // without it a failure is silent
);
```

`flush()` gives up for the round as soon as a write fails, rather than handing
the same changes to a storage that just refused them. Ask
`persistence.hasUnwrittenChanges` to know whether anything is still waiting.
After `dispose()` it reads `true` only when those edits never reached the disk.

## Peer identity

`CRDTDocument` mints a new `PeerId` when you do not pass one, so **every
restart writes under a new author**. The version vector gains 24 bytes per
session and carries them inside every snapshot from then on.

`CRDTPeerIdStorage` keeps that identity, and `backend.openDocument` reads it
for you. Reach for it by hand only when you build the document yourself — the
id has to exist **before** the document that writes under it, so this is not
something `CRDTDocumentPersistence.open` can do:

```dart
final peers = backend.peerIdStorageForDocument(documentId);

final document = CRDTDocument(
  documentId: documentId,
  peerId: await peers.loadOrCreate(), // stored the first time, read after
);
```

It stands on its own. An app that keeps no changes and no snapshots on disk
can still use this, and nothing else.

Reusing a stored id is safe: a document advances its clock past every change
it applies and every snapshot it imports, so a restored document never mints
an operation id twice. The restore happens before the first local write, which
is what that rests on.

Never let two writers share one id: an operation is identified by peer id plus
clock, so two documents writing under one id can mint the same operation
twice. One writer per document per device.

## The whole opening, in one call

Identity, then document, then restore. They have to happen in that order — the
`PeerId` before the document that writes under it — and `openDocument` is them:

```dart
final backend = CRDTSqlite.open('notes.db');

final room = await backend.openDocument('note-1');

room.document;    // already full, already the author it was last time
room.persistence; // dispose this when you are done

final text = CRDTFugueTextHandler(room.document, 'body');
```

Build the handlers on the document it hands back, as above. A handler reads its
state from the document whenever it is created, so one made after the restore
reads exactly what one made before it would have.

| argument | what it is for |
| --- | --- |
| `author` | the identity to use for a document that has none stored yet, and it is stored |
| `onDocument` | runs before the restore, for what has to exist first — a listener on `events`, the factories for nested handlers |

`writeDelay`, `compactAfter` and `onError` mean what they mean on
`CRDTDocumentPersistence.open`.

The identity is always kept. A stored id beats `author`: it is what the
document already wrote under, and writing under a second one would make one
device look like two peers.

If the restore fails the document is disposed and the failure is thrown, so you
never get half a document back. Connect the sync client **after** this returns,
never before.

Use `CRDTDocumentPersistence.open` directly where there is no backend — a
single `CRDTDocumentStorage` you wrote by hand.

## Many documents

An app has notes, not a note. `CRDTStorageBackend` is the database itself, and
every adapter is one:

```dart
final backend = CRDTSqlite.open('notes.db');

for (final documentId in await backend.documentIds) { ... }

await backend.deleteDocument('note-1');  // changes, snapshots and identity
backend.close();
```

`documentIds` lists a document once anything about it is stored, its identity
included — so a note that was created and never typed into is still there, and
still empty.

> **Hive note.** Hive cannot list its boxes, and this adapter gives every
> document a box of its own, so `CRDTHive.open()` keeps a small registry box.
> A document costs one extra row, written the first time it is opened. A
> document stored by an older version of the adapter is not on that list until
> it is opened once; its data is untouched either way.

## Reading without writing

Not every document is going to be edited. A list of fifty notes wants fifty
titles, not fifty `CRDTDocumentPersistence`s that will never write anything.

```dart
final note = await backend.readDocument('note-1');
final title = CRDTFugueTextHandler(note, 'body').value;
```

Nothing follows what it hands back: an edit made on it stays in memory. On a
synchronous backend it returns without suspending, so the whole list is built
inside one frame.

`documentAt` is the same thing with a bound — the document as it stood at a
version, which is what a history view reads:

```dart
final before = await backend.documentAt('note-1', lastWeek);
```

How far back it reaches is what the log still holds. A prune deletes the
changes a snapshot covers, so a compacted document cannot be rebuilt at a
version older than its snapshot — and it says so, by throwing, instead of
handing back a document that is quietly short.

## Backup, restore, and changing adapter

`copyDocumentTo` moves a whole document to another backend, identity included:

```dart
await hive.copyDocumentTo(sqlite, 'note-1');
```

Rows already in the target with the same ids are replaced, so copying twice
leaves what copying once left. What the target holds and the source does not is
left alone: clear it first for an exact copy.

To **duplicate** a document into a new one, go through the storages and leave
the identities out — two documents writing under one `PeerId` can mint the same
operation id twice:

```dart
await (await backend.storageForDocument('note-1'))
    .copyTo(await backend.storageForDocument('note-1-copy'));
```

## Growth

Nothing prunes on its own. The change log grows for as long as the document is
edited, and a synced document also stores what every other peer wrote.

`compactAfter` snapshots and prunes once the store holds more than that many
changes:

```dart
await CRDTDocumentPersistence.open(document, storage, compactAfter: 1000);
```

`compact()` does the same on demand — a "save and compact" button, or the
moment an app goes to the background:

```dart
await persistence.compact();
```

Both are off by default because a prune drops the stacks of every
`CRDTUndoManager` on the document. Turn `compactAfter` on for a document that
lives a long time; where undo matters more, leave it off and call `compact()`
at a moment the user cannot be in the middle of something.

## Writing an adapter

Implement `CRDTChangeStorage` and `CRDTSnapshotStorage`, and hand both back as
a `CRDTDocumentStorage`. Store `Change.toBytes()` and `Snapshot.toBytes()` as
opaque blobs, keyed by `Change.id` and `Snapshot.id`; do not interpret them.

`CRDTDocumentStorage` adds two more, and both already work:

| member | default | override it when |
| --- | --- | --- |
| `close()` | does nothing | the backend opens something **per document** |
| `transaction(body)` | runs `body` | the backend has transactions |

Leave them alone and the adapter is still correct. `transaction` is what makes
a prune all-or-nothing — it drops the changes the snapshot covers and rewrites
the survivors, whose bytes changed. It also writes the snapshot and drops the
one before it. Without it those steps are separate, and every step is safe to
repeat anyway.

One rule if you do implement it: **a `body` that returns without suspending
must be carried through without suspending.** On a backend where one
connection serves every document, a suspension inside an open transaction lets
another document write into it, and a rollback then takes that write with it —
silently, since the transaction that lost the write never saw an error. `close()` releases what belongs to **this
document only**: a connection shared between documents stays open, and the
backend closes that itself.

`CRDTPeerIdStorage` is separate. Implement it to let a document keep the
identity it writes under; two methods, and the value is a string
(`PeerId.toString()` / `PeerId.parse`). It is needed before the document
exists, so it comes from the backend rather than from `CRDTDocumentStorage`.

Then implement `CRDTStorageBackend` on your entry point — the class that owns
the database. Five members, and four of them you already have:

| member | what it answers |
| --- | --- |
| `storageForDocument(id)` | the changes and snapshots of one document |
| `peerIdStorageForDocument(id)` | the identity of one document |
| `documentIds` | every document this backend holds |
| `deleteDocument(id)` | drop all three of them |
| `close()` | let the database go; twice is not an error |

`documentIds` is the one that needs thought. A backend with a `document_id`
column answers it with a `UNION` over the three tables — the third one matters,
because a document that was created and never written to exists only as an
identity. A backend that cannot ask the question has to write the ids down
itself, which is what the Hive adapter does.

Return a plain value wherever the backend can. Every method is declared
`FutureOr`, so narrowing the return type to `List<Change>` or `void` is a
legal override, and it is what lets `openSync` work. Use `filterByVersion` for
the two version-vector bounds of `getChanges` unless the backend can ask its
own query language.

Then check the adapter against the shared conformance suite — it is what the
three official adapters run:

```dart
import 'package:persistence_conformance/persistence_conformance.dart';

void main() {
  runDocumentStorageConformanceTests(
    name: 'MyStorage',
    open: (documentId) => MyStorage.open(documentId),
    // Turn these on for what the backend really does.
    atomicTransactions: true,
    synchronous: true,
    openPeerIds: (documentId) => MyPeerIds.open(documentId),
  );

  runStorageBackendConformanceTests(
    name: 'MyBackend',
    open: () => MyBackend.open(path),
    // Leave this out for a backend that cannot be reopened on the same data.
    reopen: (_) => MyBackend.open(path),
  );
}
```

[`example/main.dart`](example/main.dart) keeps the whole contract in a map —
the shortest version of what you are about to write.

`persistence_conformance` is internal and unpublished, so an adapter outside
this repository cannot depend on it. Read
[the suite](https://github.com/MattiaPispisa/crdt/tree/main/packages/_internal/persistence_conformance)
and copy what it checks.

## Apps

- [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) — Real-time collaborative markdown editor built on crdt_lf

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)
