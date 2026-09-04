# CRDT LF SQLite

[![crdt_lf_sqlite_badge][crdt_lf_sqlite_badge]](https://pub.dev/packages/crdt_lf_sqlite)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

- [CRDT LF SQLite](#crdt-lf-sqlite)
  - [Features](#features)
  - [Quick Start](#quick-start)
    - [1. Open a database](#1-open-a-database)
    - [2. Document-scoped storage](#2-document-scoped-storage)
  - [Document-Scoped Storage](#document-scoped-storage)
    - [CRDTSqliteChangeStorage](#crdtsqlitechangestorage)
    - [CRDTSqliteSnapshotStorage](#crdtsqlitesnapshotstorage)
  - [How Data Is Stored](#how-data-is-stored)
  - [Examples](#examples)
  - [Storage Management](#storage-management)
  - [Roadmap](#roadmap)
  - [Packages](#packages)

A [sqlite3](https://pub.dev/packages/sqlite3) storage implementation for [CRDT LF](https://pub.dev/packages/crdt_lf) objects, providing efficient persistence for `Change` and `Snapshot` objects with document-scoped organization in a single SQLite database.

## Features

- **Compact Binary Storage**: `Change` and `Snapshot` are persisted as the self-describing binary blobs produced by `crdt_lf`'s native `toBytes()` / `fromBytes()` methods
- **Single Database, Many Documents**: one database holds `changes` and `snapshots` tables
- **Document-Scoped Storage**: utilities that organize data by document ID for better isolation and querying
- **Nothing suspends**: `sqlite3` is synchronous (FFI), and every storage method here says so in its return type. That is also what lets `CRDTDocumentPersistence.openSync` restore a document before it returns

## Quick Start

### 1. Open a database

```dart
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

void main() {
  // Open (or create) a database file...
  final storage = CRDTSqlite.open('./my_app_data.db');

  // ...or an in-memory database (useful for tests):
  final memory = CRDTSqlite.memory();

  // Your app code here...

  storage.close();
}
```

### 2. Document-scoped storage

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

const documentId = 'my-document-id';

final storage = CRDTSqlite.open('./my_app_data.db');

// Open storage for a specific document
final changeStorage = storage.changeStorageForDocument(documentId);
final snapshotStorage = storage.snapshotStorageForDocument(documentId);

// Or open both at once
final documentStorage = storage.storageForDocument(documentId);
```

## Keeping a whole document on disk

Most apps do not call these methods by hand. Hand the storage to
`CRDTDocumentPersistence` instead: it reads the document back, then follows it
and writes down what moves.

```dart
final document = CRDTDocument(documentId: documentId);
final persistence = await CRDTDocumentPersistence.open(
  document,
  storage.storageForDocument(documentId),
);
```

It comes from [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence),
which this package re-exports. See that README for the offline-first rules.

`storageForDocument` hands back a `CRDTSqliteDocumentStorage`, which backs
`transaction()` with a real SQLite transaction: a prune drops the covered
changes and rewrites the survivors, and either all of it lands or none of it
does. It is built on savepoints, so a batch that opens a transaction of its own
nests inside instead of failing.

`close()` on it does nothing on purpose. One database file holds every
document, so the connection is `CRDTSqlite.close()`'s to release.

## Document-Scoped Storage

Data for different documents lives in the same tables and is isolated through the `document_id` column.

Every method answers on the spot. sqlite3 is synchronous underneath, and the
return types say so: `getChanges()` gives a `List<Change>`, `saveChange()`
gives `void`. The shared contract asks only for a `FutureOr`, so the same code
still runs on drift — but here there is nothing to `await`.

### CRDTSqliteChangeStorage

Manages `Change` objects for a specific document:

```dart
final changeStorage = storage.changeStorageForDocument('doc-123');

// Save individual changes
changeStorage.saveChange(change);

// Batch save multiple changes
changeStorage.saveChanges([change1, change2, change3]);

// Load all changes for the document
final changes = changeStorage.getChanges();

// Or only part of the log, by version vector
final missing = changeStorage.getChanges(newerThan: theirVersion);
final past = changeStorage.getChanges(upTo: oldVersion);

// Delete changes
changeStorage.deleteChange(change);
changeStorage.deleteChanges([change1, change2]);

// Storage info
print('Total changes: ${changeStorage.count}');
```

### CRDTSqliteSnapshotStorage

Manages `Snapshot` objects for a specific document:

```dart
final snapshotStorage = storage.snapshotStorageForDocument('doc-123');

// Save snapshots
snapshotStorage.saveSnapshot(snapshot);
snapshotStorage.saveSnapshots([snapshot1, snapshot2]);

// Retrieve snapshots
final snapshot = snapshotStorage.getSnapshot('snapshot-id');
final allSnapshots = snapshotStorage.getSnapshots();

// Check existence
if (snapshotStorage.containsSnapshot('snapshot-id')) {
  // Snapshot exists
}
```

### CRDTSqlitePeerIdStorage

Keeps the `PeerId` the document writes under, in the `peers` table. Without it
`CRDTDocument` mints a new author on every restart, and the version vector
grows by one peer per session.

Read it **before** building the document — the id has to exist first:

```dart
final peers = storage.peerIdStorageForDocument('doc-123');

final document = CRDTDocument(
  documentId: 'doc-123',
  peerId: peers.loadOrCreate() as PeerId, // synchronous here
);
```

## How Data Is Stored

Both `Change` and `Snapshot` are stored as opaque binary blobs using the
self-describing format provided by `crdt_lf` (`toBytes()` / `fromBytes()`). The
schema is two tables:

```sql
CREATE TABLE changes (
  document_id TEXT NOT NULL,
  change_id   TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, change_id)
);

CREATE TABLE snapshots (
  document_id TEXT NOT NULL,
  snapshot_id TEXT NOT NULL,
  bytes       BLOB NOT NULL,
  PRIMARY KEY (document_id, snapshot_id)
);
```

Changes are keyed by `change.id`, snapshots by `snapshot.id`.

## Examples

A complete example is available [here](https://github.com/MattiaPispisa/crdt/blob/main/packages/adapters/persistence/crdt_lf_sqlite/example/main.dart).

## Storage Management

```dart
// Delete all data for a specific document
storage.deleteDocumentData('doc-123');

// Close the database and release resources
storage.close();
```

## Roadmap
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.

## Apps

- [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) — Real-time collaborative markdown editor built on crdt_lf

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_persistence](https://pub.dev/packages/crdt_lf_persistence)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)

[crdt_lf_sqlite_badge]: https://img.shields.io/pub/v/crdt_lf_sqlite.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_lf_sqlite&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/adapters/persistence/crdt_lf_sqlite
[pub_link]: https://pub.dev/packages/crdt_lf_sqlite
[pub_points]: https://img.shields.io/pub/points/crdt_lf_sqlite
[pub_likes]: https://img.shields.io/pub/likes/crdt_lf_sqlite
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_publisher]: https://img.shields.io/pub/publisher/crdt_lf_sqlite
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
