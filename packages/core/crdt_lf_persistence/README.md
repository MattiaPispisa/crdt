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
```

Run it again and the text is there. A runnable version is in
[`crdt_lf_sqlite`'s example](https://github.com/MattiaPispisa/crdt/blob/main/packages/adapters/persistence/crdt_lf_sqlite/example/main.dart).

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

Then check the adapter against the shared conformance suite — it is what the
three official adapters run:

```dart
import 'package:persistence_conformance/persistence_conformance.dart';

void main() {
  runDocumentStorageConformanceTests(
    name: 'MyStorage',
    open: (documentId) => MyStorage.open(documentId),
  );
}
```

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
