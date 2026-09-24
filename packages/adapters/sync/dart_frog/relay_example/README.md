# crdt_socket_sync_dart_frog example — relay mode

A Dart Frog backend serving the `crdt_socket_sync` relay mode on `/relay`: the
server rebroadcasts opaque CRDT change blobs to the other clients of a room
and persists them, without ever reading them. Merging is a client concern.

```sh
dart pub get
dart_frog dev
```

Then point a `WebSocketRelayClient` at `ws://localhost:8080/relay`. The room
is the document id inside the hello frame, not part of the path.

For the server–client mode see [`../example`](../example).

## What to look at

- **`lib/src/host.dart`** — a `RelaySessionHost` over an `InMemoryRelayStore`,
  built at the top level so `_middleware.dart` finds it. A restart loses every
  room: there is no durable `RelayStore` in this repository yet, so a real
  backend implements one over its database.
- **`main.dart`** — the two hooks Dart Frog offers. `init()` runs once, before
  the handler tree is built: it starts the host and disposes it on
  `SIGINT`/`SIGTERM`. `run()` only serves. Keep it that way: `dart_frog dev`
  calls `run()` again on every hot reload, so anything registered there piles
  up.
- **`routes/relay.dart`** — the route. Authenticate here, before the upgrade,
  the same way `../example/routes/sync.dart` does.
- **`routes/_middleware.dart`** — puts the host in the context.

## Notes

- `melos run analyze` covers `lib` and `test` only, so `routes/` and `main.dart`
  are not analyzed by it. Run `dart analyze routes main.dart` for those.
- There is nothing here to unit-test: every line that is not wiring belongs to
  `crdt_socket_sync` or to the adapter, and is tested there.
- `dart_frog build` does not work from inside this monorepo: the example depends
  on its own parent package through a path override, and the production build
  copies path dependencies into `build/`, which it cannot do for an ancestor
  directory. It builds normally in a project that takes
  `crdt_socket_sync_dart_frog` from pub.dev.
