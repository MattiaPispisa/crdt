# CRDT LF SQLite

[![crdt_lf_sqlite_badge][crdt_lf_sqlite_badge]](https://pub.dev/packages/crdt_lf_sqlite)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

A [sqlite3](https://pub.dev/packages/sqlite3) storage adapter for [`crdt_lf`](https://pub.dev/packages/crdt_lf):
it keeps your documents on the device, and reads them back on launch. Nothing suspends: every call answers on the spot.

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full persistence guide — which adapter to pick, history, backups, compaction — is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/connectors/persistence).**

## Features

- ⚡ **Synchronous**: no `await` in the way, and a document is restored before the first frame
- 🗄️ **One file, many documents**: three tables, inspect them with any SQLite tool
- 🔒 **Real transactions**: a compaction lands all at once or not at all
- 📦 **Compact binary**: each change and snapshot as one blob
- 🪪 **Peer identity**: the device writes under the same author on every launch
- 🧩 **Same contract** as the Hive and Drift adapters: change backend with one line
- ➕ **…and more**: everything else is in the [documentation][docs_link]

## Quick start

```sh
dart pub add crdt_lf crdt_lf_sqlite
```

<!-- recipe:persisted-note/main.dart#imports,open,edit,close -->
```dart
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

final backend = CRDTSqlite.open('note.db');

// Reads the stored note (or starts an empty one), then writes every edit.
final note = await backend.openDocument('note');
final text = CRDTFugueTextHandler(note.document, 'body');

text.insert(text.value.runes.length, 'Hello 🌍\n');

await note.persistence.dispose(); // writes what is still waiting
note.document.dispose();
await note.persistence.storage.close();
backend.close();
```
<!-- /recipe -->

Every change is written down from there on: the complete program, tested in
CI, is the [recipe](https://mattiapispisa.it/crdt/docs/recipes/persisted-note). This package re-exports the whole
[`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence) API, so it
is the only storage package your `pubspec.yaml` needs.

## Documentation

- [Which adapter](https://mattiapispisa.it/crdt/docs/connectors/persistence#which-adapter): Hive, SQLite, Drift, …
- [SQLite: setup and storage details](https://mattiapispisa.it/crdt/docs/connectors/persistence/adapters)
- [Working with storage](https://mattiapispisa.it/crdt/docs/connectors/persistence/working-with-storage):
  history, backups, compaction, …
- [Open a replica](https://mattiapispisa.it/crdt/docs/connectors/replica): storage and sync together

## Roadmap

<div align="center">

[![Roadmap: done, in progress, to do][roadmap_badge]][roadmap_link]

</div>

🗺️ The [project board](https://github.com/users/MattiaPispisa/projects/1) shows what is done, what is in progress and
what comes next, for this package and the rest of the workspace. Missing something?
[Open an issue](https://github.com/MattiaPispisa/crdt/issues/new/choose): requests go on the board too.

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
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

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
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/connectors/persistence/adapters
[roadmap_badge]: https://img.shields.io/badge/%F0%9F%97%BA%EF%B8%8F%20Roadmap-done%20%C2%B7%20in%20progress%20%C2%B7%20to%20do-d04848?style=for-the-badge
[roadmap_link]: https://github.com/users/MattiaPispisa/projects/1
