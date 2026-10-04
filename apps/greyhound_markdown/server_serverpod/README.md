# Greyhound Markdown — Serverpod relay server

A local relay server for the Greyhound Markdown client, built with
[`crdt_socket_sync_serverpod`](../../../packages/adapters/sync/serverpod). It
serves the `crdt_socket_sync` relay protocol on `ws://localhost:8787/room/<id>`,
the same address as `wrangler dev`, so the client connects with no extra
setting. Serverpod's API server takes port 8788 and has no endpoints.

```sh
fvm dart pub get
fvm dart run bin/main.dart
```

Or start the `🐕 🖥️ greyhound_markdown server [serverpod]` launch
configuration in VS Code.

It is for local testing only:

- Rooms live in memory (`InMemoryRelayStore`): a restart empties them.
- Any origin may connect (`allowAnyOrigin: true`).
- The pod has no database and no generated code: `lib/src/server_protocol.dart`
  holds an empty protocol and endpoint dispatch.

## What to look at

- `lib/src/host.dart` — the `RelaySessionHost`, with the awareness plugin
  the client's shared cursors need.
- `bin/main.dart` — the pod, the `CrdtRelayRoute` on `/room/:id`, and the
  shutdown task that disposes the host.
