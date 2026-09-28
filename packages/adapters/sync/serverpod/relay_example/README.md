# crdt_socket_sync_serverpod example — relay mode

A Serverpod backend serving the `crdt_socket_sync` relay mode on `/relay`: the
server rebroadcasts opaque CRDT change blobs to the other clients of a room
and persists them, without ever reading them. Merging is a client concern.

```sh
dart pub get
dart run bin/main.dart
```

Then point a `WebSocketRelayClient` at `ws://localhost:8080/relay`. The room
is the document id inside the hello frame, not part of the path. Stop the
server with `Ctrl+C`.

For the server–client mode see [`../example`](../example).

## What to look at

- **`lib/src/host.dart`** — a `RelaySessionHost` over an `InMemoryRelayStore`.
  A restart loses every room: there is no durable `RelayStore` in this
  repository yet, so a real backend implements one over its database.
- **`bin/main.dart`** — builds the pod and adds a `CrdtRelayRoute` to its web
  server. Serverpod handles `SIGINT`/`SIGTERM` itself, so the host is disposed
  in a shutdown task (`pod.experimental.shutdownTasks`), which runs after the
  web server has stopped. To authenticate, subclass the route the way
  `../example/bin/main.dart` does.
- **`lib/src/server_protocol.dart`** — an empty protocol and endpoint
  dispatch, so the example runs without code generation and without a
  database.

## Notes

- There is nothing here to unit-test: every line that is not wiring belongs to
  `crdt_socket_sync` or to the adapter, and is tested there.
- A real Serverpod project passes its generated `Protocol()` and
  `Endpoints()` instead of the stubs.
