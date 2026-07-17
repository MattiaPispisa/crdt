# CRDT LF Drift

[![crdt_lf_drift_badge][crdt_lf_drift_badge]](https://pub.dev/packages/crdt_lf_drift)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

- [CRDT LF Drift](#crdt-lf-drift)
  - [Features](#features)
  - [Quick Start](#quick-start)
    - [1. Open a database](#1-open-a-database)
    - [2. Document-scoped storage](#2-document-scoped-storage)
  - [Document-Scoped Storage](#document-scoped-storage)
    - [CRDTDriftChangeStorage](#crdtdriftchangestorage)
    - [CRDTDriftSnapshotStorage](#crdtdriftsnapshotstorage)
  - [How Data Is Stored](#how-data-is-stored)
  - [Examples](#examples)
  - [Storage Management](#storage-management)
  - [Important Notes](#important-notes)
  - [Roadmap](#roadmap)
  - [Packages](#packages)

A [drift](https://pub.dev/packages/drift) storage implementation for [CRDT LF](https://pub.dev/packages/crdt_lf) objects, providing efficient persistence for `Change` and `Snapshot` objects with document-scoped organization in a single drift database.

## Features

- **Compact Binary Storage**: `Change` and `Snapshot` are persisted as the self-describing binary blobs produced by `crdt_lf`'s native `toBytes()` / `fromBytes()` methods
- **Single Database, Many Documents**: one database holds `changes` and `snapshots` tables; 
- **Document-Scoped Storage**: utilities that organize data by document ID for better isolation and querying

## Quick Start

### 1. Open a database

```dart
import 'dart:io';

import 'package:crdt_lf_drift/crdt_lf_drift.dart';

Future<void> main() async {
  // Open (or create) a database file...
  final storage = CRDTDrift.open(File('./my_app_data.db'));

  // ...or an in-memory database (useful for tests):
  final memory = CRDTDrift.memory();

  // Your app code here...

  await storage.close();
}
```

### 2. Document-scoped storage

```dart
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';

const documentId = 'my-document-id';

final storage = CRDTDrift.open(File('./my_app_data.db'));

// Open storage for a specific document
final changeStorage = storage.changeStorageForDocument(documentId);
final snapshotStorage = storage.snapshotStorageForDocument(documentId);

// Or open both at once
final documentStorage = storage.storageForDocument(documentId);
```

## Document-Scoped Storage

Data for different documents lives in the same tables and is isolated through the `document_id` column.

### CRDTDriftChangeStorage

Manages `Change` objects for a specific document:

```dart
final changeStorage = storage.changeStorageForDocument('doc-123');

// Save individual changes
await changeStorage.saveChange(change);

// Batch save multiple changes
await changeStorage.saveChanges([change1, change2, change3]);

// Load all changes for the document
final changes = await changeStorage.getChanges();

// Delete changes
await changeStorage.deleteChange(change);
await changeStorage.deleteChanges([change1, change2]);

// Storage info
print('Total changes: ${await changeStorage.count}');
print('Is empty: ${await changeStorage.isEmpty}');
```

### CRDTDriftSnapshotStorage

Manages `Snapshot` objects for a specific document:

```dart
final snapshotStorage = storage.snapshotStorageForDocument('doc-123');

// Save snapshots
await snapshotStorage.saveSnapshot(snapshot);
await snapshotStorage.saveSnapshots([snapshot1, snapshot2]);

// Retrieve snapshots
final snapshot = await snapshotStorage.getSnapshot('snapshot-id');
final allSnapshots = await snapshotStorage.getSnapshots();

// Check existence
if (await snapshotStorage.containsSnapshot('snapshot-id')) {
  // Snapshot exists
}
```

## How Data Is Stored

Both `Change` and `Snapshot` are stored as opaque binary blobs using the
self-describing format provided by `crdt_lf` (`toBytes()` / `fromBytes()`). The
schema is two tables, `changes` and `snapshots`, each with a `document_id`
column, an id column (`change_id` / `snapshot_id`) and a `bytes` blob column.
Changes are keyed by `change.id`, snapshots by `snapshot.id`.

## Examples

A complete example is available [here](https://github.com/MattiaPispisa/crdt/blob/main/packages/crdt_lf_drift/example/main.dart).

## Storage Management

```dart
// Delete all data for a specific document
await storage.deleteDocumentData('doc-123');

// Close the database and release resources
await storage.close();
```

## Roadmap
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)


[crdt_lf_drift_badge]: https://img.shields.io/pub/v/crdt_lf_drift.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_lf_drift&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/crdt_lf_drift
[pub_link]: https://pub.dev/packages/crdt_lf_drift
[pub_points]: https://img.shields.io/pub/points/crdt_lf_drift
[pub_likes]: https://img.shields.io/pub/likes/crdt_lf_drift
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_publisher]: https://img.shields.io/pub/publisher/crdt_lf_drift
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
