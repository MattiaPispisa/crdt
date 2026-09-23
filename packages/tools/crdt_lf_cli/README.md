# crdt_lf_cli

A command-line tool that generates [crdt_lf](https://pub.dev/packages/crdt_lf)
projects. You answer a few questions and get a project that already runs: a
sync server, the storage behind it and the document both sides share.

## Install

```sh
dart pub global activate crdt_lf_cli
```

## Create a project

```sh
crdt_lf create notes
```

The command asks for every choice. Pass a flag to skip its question:

```sh
crdt_lf create notes --server plain --server-storage sqlite --handler fugue_text
```

| Flag | Values | Default |
|---|---|---|
| `--server` | `plain` | `plain` |
| `--server-storage` | `infrastructure`, `hive`, `drift`, `sqlite` | `sqlite` |
| `--handler` | `none`, `fugue_text` | `fugue_text` |
| `-o`, `--output-directory` | a folder | `.` |
| `--[no-]interactive` | ask the questions without a flag | on |
| `--[no-]pub-get` | run `dart pub get` at the end | on |

With `--no-interactive`, or without a terminal, a choice without its flag
takes its default.

`infrastructure` gives a storage backend to write by hand: every method is
there and throws `UnimplementedError` until you write it. The server test is
skipped until then.

## What you get

A [pub workspace](https://dart.dev/tools/pub/workspaces):

```
notes/
  pubspec.yaml         the workspace
  notes_shared/        the document id and its handlers
    lib/src/schema.dart
  notes_server/        a crdt_socket_sync WebSocket server
    bin/server.dart
    lib/src/server.dart
    lib/src/storage.dart
    test/server_test.dart
```

- `schema.dart` opens the handlers of the document. Client and server both
  call it, so they agree on what the document holds.
- `storage.dart` opens the storage backend. It is the only file that changes
  between Hive, Drift, SQLite and a backend written by hand.
- `server_test.dart` starts the server, sends a change from one client to
  another, restarts the server and checks the change is still there.

## How it works

Each choice is a small [mason](https://pub.dev/packages/mason) brick in
`bricks/`. A brick owns its own files and never writes a file of another
brick, so the bricks compose without merging. A new storage adapter is one
brick that writes `lib/src/storage.dart`, plus its packages in
`lib/src/project/project_plan.dart`.

The CLI computes the dependencies of each package and passes them to the
brick that writes its `pubspec.yaml`. The versions live in
`lib/src/project/versions.dart`.

## Develop

After changing a brick, rebuild the Dart bundles:

```sh
dart run tool/generate_bundles.dart
```

A test fails when a bundle is older than its brick.

`dart test` runs the fast tests. The end-to-end tests generate every
project, resolve it against the packages of this repository and run its
tests:

```sh
dart test --run-skipped -t e2e
```
