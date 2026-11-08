# CRDT LF Persistence

[![crdt_lf_persistence_badge][crdt_lf_persistence_badge]](https://pub.dev/packages/crdt_lf_persistence)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

The **storage contract** behind the [`crdt_lf`](https://pub.dev/packages/crdt_lf)
persistence adapters, and the code that keeps a document on disk as it changes.

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full persistence guide — choosing an adapter, history, backups, compaction, writing an adapter — is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/connectors/persistence).**

> ⚠️ **Do not put this package in your `pubspec.yaml`.** Pick an adapter: it
> re-exports this whole API.

| Adapter | Database |
| --- | --- |
| [`crdt_lf_hive`](https://pub.dev/packages/crdt_lf_hive) | Hive (NoSQL, runs on the web) |
| [`crdt_lf_sqlite`](https://pub.dev/packages/crdt_lf_sqlite) | sqlite3 (SQL, synchronous) |
| [`crdt_lf_drift`](https://pub.dev/packages/crdt_lf_drift) | Drift (SQL, asynchronous) |

## Features

- 📂 **One call to open**: identity, document and restore, in the right order
- ✍️ **Writes itself**: follows the document and writes down every change, batched
- 🔁 **Retries**: a failed write is retried with backoff, and nothing is lost
- ✅ **Durability you can wait for**: `whenStored(version)`
- 🗜️ **Compaction**: snapshot and prune, on a threshold or on demand
- 🕰️ **History**: read a document as it was at a version
- 📦 **Backup and move**: copy a document to another adapter
- 🧩 **One contract**: change adapter by changing one line

## Quick start

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

## Documentation

- [Which adapter](https://mattiapispisa.it/crdt/docs/connectors/persistence#which-adapter): SQL or NoSQL, sync or async
- [Working with storage](https://mattiapispisa.it/crdt/docs/connectors/persistence/working-with-storage):
  history, backups, compaction
- [How it works](https://mattiapispisa.it/crdt/docs/connectors/persistence/how-it-works): batching, retries,
  durability, peer identity
- [Build your own adapter](https://mattiapispisa.it/crdt/docs/connectors/persistence/build-your-own): the
  contract and the conformance suite

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
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

[crdt_lf_persistence_badge]: https://img.shields.io/pub/v/crdt_lf_persistence.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_lf_persistence&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf_persistence
[pub_link]: https://pub.dev/packages/crdt_lf_persistence
[pub_points]: https://img.shields.io/pub/points/crdt_lf_persistence
[pub_likes]: https://img.shields.io/pub/likes/crdt_lf_persistence
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_publisher]: https://img.shields.io/pub/publisher/crdt_lf_persistence
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/connectors/persistence
