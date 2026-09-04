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

Two things live here:

- **`CRDTDocumentStorage`** — what a backend has to provide. `crdt_lf_hive`,
  `crdt_lf_drift` and `crdt_lf_sqlite` all implement it, so code written
  against it runs on any of them.
- **`CRDTDocumentPersistence`** — the part you would otherwise write yourself:
  read the document back, then follow it and write down what moves.

## Local only

No server to talk to: a document, an adapter, and the two lines between them.
One import, the adapter's.

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

const documentId = 'note';
final database = CRDTSqlite.open('note.db');

final document = CRDTDocument(documentId: documentId);
final text = CRDTFugueTextHandler(document, 'body');

// Reads the database into the document, then follows it.
final persistence = await CRDTDocumentPersistence.open(
  document,
  database.storageForDocument(documentId),
);

text.insert(0, 'Hello 🌍');

await persistence.dispose(); // writes what is still waiting
database.close();
```

Run it again and the text is there.
[`crdt_lf_sqlite`'s example](https://github.com/MattiaPispisa/crdt/blob/main/packages/adapters/persistence/crdt_lf_sqlite/example/main.dart)
is that, runnable.

[`example/main.dart`](example/main.dart) here takes the other side: it keeps
the contract in a map, so you can read what an adapter has to fill in.

## Offline-first, with sync

Same two lines, plus one rule: **open the persistence before you connect.**

```dart
final document = CRDTDocument(documentId: roomId);
final persistence = await CRDTDocumentPersistence.open(document, storage);

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

A write that fails keeps what it carried. The changes stay queued and the next
`flush()` tries the whole batch again — saving a change twice replaces it, so a
write that half landed costs nothing.

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

`CRDTPeerIdStorage` keeps that identity. Read it **before** you build the
document — the id has to exist before the document that writes under it, so
this is not something `CRDTDocumentPersistence.open` can do for you:

```dart
final peers = database.peerIdStorageForDocument(documentId);

final document = CRDTDocument(
  documentId: documentId,
  peerId: await peers.loadOrCreate(), // stored the first time, read after
);
```

It stands on its own. An app that keeps no changes and no snapshots on disk
can still use this, and nothing else.

Reusing a stored id is safe: a document advances its clock past every change
it applies and every snapshot it imports, so a restored document never mints
an operation id twice. `open` restores before the first local write, which is
what that rests on.

Never let two writers share one id: an operation is identified by peer id plus
clock, so two documents writing under one id can mint the same operation
twice. One writer per document per device.

## Growth

Nothing prunes on its own. The change log grows for as long as the document is
edited, and a synced document also stores what every other peer wrote.

`compactAfter` snapshots and prunes once the store holds more than that many
changes:

```dart
await CRDTDocumentPersistence.open(document, storage, compactAfter: 1000);
```

It is off by default because a prune drops the stacks of every
`CRDTUndoManager` on the document. Turn it on for a document that lives a long
time, and leave it off where undo matters more.

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

`CRDTPeerIdStorage` is separate, and optional. Implement it to let a document
keep the identity it writes under; two methods, and the value is a string
(`PeerId.toString()` / `PeerId.parse`). Hand it out from your own entry point,
not from `CRDTDocumentStorage`: it is needed before the document exists.

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
