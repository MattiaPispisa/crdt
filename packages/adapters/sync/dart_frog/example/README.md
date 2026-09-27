# crdt_socket_sync_dart_frog example — server–client mode

A Dart Frog backend serving the `crdt_socket_sync` server–client mode on
`/sync`: the server holds the document, validates the changes and takes
aligned snapshots. The documents live in Hive, through
[`crdt_lf_hive`](https://pub.dev/packages/crdt_lf_hive), so they survive a
restart.

```sh
dart pub get
dart_frog dev
```

Then point a `WebSocketClient` at `ws://localhost:8080/sync` with the document
id `example-document`: the handshake is refused for anything the registry does
not hold. The database is written to `db/` in this directory.

For the relay mode see [`../relay_example`](../relay_example).

## What to look at

- **`lib/src/host.dart`** — a `DocumentSessionHost` over a
  `PersistentServerRegistry` backed by Hive. The registry does the storing;
  the class only says where and owns the lifecycle: open and register the
  document in `open()`, and on `dispose()` close the host (which flushes and
  closes the registry), then every Hive box.
- **`main.dart`** — the two hooks Dart Frog offers. `init()` runs once, before
  the handler tree is built: it opens the host and disposes it on
  `SIGINT`/`SIGTERM` (Dart Frog has no shutdown hook, so signals are where an
  orderly teardown goes — with a durable registry that is what flushes the
  writes still waiting). `run()` only serves. Keep it that way: `dart_frog dev`
  calls `run()` again on every hot reload, so anything registered there piles
  up.
- **`routes/sync.dart`** — has a token check in front of the handler, to show
  the point of doing this in a route: the request exists before the socket
  does, so a client that fails it gets a plain `401` and never reaches the
  protocol. Send `Authorization: Bearer example-token`, or no header at all.
- **`routes/_middleware.dart`** — puts the host in the context.

## Notes

- `melos run analyze` covers `lib` and `test` only, so `routes/` and `main.dart`
  are not analyzed by it. Run `dart analyze routes main.dart` for those.
- `dart_frog build` does not work from inside this monorepo: the example depends
  on its own parent package through a path override, and the production build
  copies path dependencies into `build/`, which it cannot do for an ancestor
  directory. It builds normally in a project that takes
  `crdt_socket_sync_dart_frog` from pub.dev.
