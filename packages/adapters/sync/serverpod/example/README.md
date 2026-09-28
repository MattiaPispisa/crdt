# crdt_socket_sync_serverpod example — server–client mode

A Serverpod backend serving the `crdt_socket_sync` server–client mode on
`/sync`: the server holds the document, validates the changes and takes
aligned snapshots. The documents live in Hive, through
[`crdt_lf_hive`](https://pub.dev/packages/crdt_lf_hive), so they survive a
restart.

```sh
dart pub get
dart run bin/main.dart
```

Then point a `WebSocketClient` at `ws://localhost:8080/sync` with the document
id `example-document`: the handshake is refused for anything the registry does
not hold. The database is written to `db/` in this directory. Stop the server
with `Ctrl+C`.

For the relay mode see [`../relay_example`](../relay_example).

## What to look at

- **`lib/src/host.dart`** — a `DocumentSessionHost` over a
  `PersistentServerRegistry` backed by Hive. The registry does the storing;
  the class only says where and owns the lifecycle: open and register the
  document in `open()`, and on `dispose()` close the host (which flushes and
  closes the registry), then every Hive box.
- **`bin/main.dart`** — builds the pod and adds the route to its web server.
  Serverpod handles `SIGINT`/`SIGTERM` itself, so the host is disposed in a
  shutdown task (`pod.experimental.shutdownTasks`). These tasks run after the
  web server has stopped. With a durable registry, that is what flushes the
  writes still waiting.
- **`ExampleSyncRoute`** in `bin/main.dart` — a `CrdtSyncRoute` with a token
  check in `handleCall`, to show the point of doing this in a route: the
  request exists before the socket does, so a client that fails it gets a
  plain `401` and never reaches the protocol. The token goes through the
  pod's `authenticationHandler`, and the route reads `session.isUserSignedIn`.
  Send `Authorization: Bearer example-token`, or no header at all.
- **`lib/src/server_protocol.dart`** — an empty protocol and endpoint
  dispatch, so the example runs without code generation and without a
  database.

## Notes

- Serverpod needs an `authenticationHandler` for any request that carries an
  `Authorization` header: without one, the request fails with a `500` before
  the route runs. A malformed header gets a `400`, also before the route.
- A real Serverpod project passes its generated `Protocol()` and
  `Endpoints()` instead of the stubs, and can use `serverpod_auth` for the
  handler.
