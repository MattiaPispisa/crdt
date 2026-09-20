# crdt_socket_sync_dart_frog example

A Dart Frog backend serving both `crdt_socket_sync` modes at once:

| Route | Mode | Client |
| --- | --- | --- |
| `/relay` | relay — opaque blobs rebroadcast per room | `WebSocketRelayClient` |
| `/sync` | server–client — the server holds the document | `WebSocketClient` |

```sh
dart pub get
dart_frog dev
```

Then point a client at `ws://localhost:8080/relay` or `ws://localhost:8080/sync`.
The `/sync` route serves one document, `example-document`: the handshake is
refused for anything the registry does not hold.

## What to look at

- **`lib/src/hosts.dart`** — the two hosts, built at the top level so
  `_middleware.dart` finds them. Construction is synchronous; everything async
  lives in `start()`.
- **`main.dart`** — the two hooks Dart Frog offers. `init()` runs once, before
  the handler tree is built: it starts the hosts and disposes them on
  `SIGINT`/`SIGTERM` (Dart Frog has no shutdown hook, so signals are where an
  orderly teardown goes; with a durable registry that is what flushes the
  writes still waiting). `run()` only serves. Keep it that way: `dart_frog dev` calls
  `run()` again on every hot reload, so anything registered there piles up.
- **`routes/sync.dart`** — has a token check in front of the handler, to show
  the point of doing this in a route: the request exists before the socket
  does, so a client that fails it gets a plain `401` and never reaches the
  protocol. Send `Authorization: Bearer example-token`, or no header at all.
- **`routes/_middleware.dart`** — puts both hosts in the context.

Both stores are in-memory: a restart loses everything. Swap in a
`PersistentServerRegistry` (with `crdt_lf_hive`, `crdt_lf_sqlite` or
`crdt_lf_drift`) and a durable `RelayStore` for anything real.

## Notes

- `melos run analyze` covers `lib` and `test` only, so `routes/` and `main.dart`
  are not analyzed by it. Run `dart analyze routes main.dart` for those.
- `dart_frog build` does not work from inside this monorepo: the example depends
  on its own parent package through a path override, and the production build
  copies path dependencies into `build/`, which it cannot do for an ancestor
  directory. It builds normally in a project that takes
  `crdt_socket_sync_dart_frog` from pub.dev.
