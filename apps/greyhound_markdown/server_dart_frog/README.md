# Greyhound Markdown — Dart Frog relay server

A local relay server for the Greyhound Markdown client, built with
[`crdt_socket_sync_dart_frog`](../../../packages/adapters/sync/dart_frog). It
serves the `crdt_socket_sync` relay protocol on `ws://localhost:8787/room/<id>`,
the same address as `wrangler dev`, so the client connects with no extra
setting.

```sh
dart pub global activate dart_frog_cli   # once
fvm dart pub get
fvm exec dart_frog dev --port 8787
```

Or start the `🐕 🖥️ greyhound_markdown server [dart_frog]` launch
configuration in VS Code.

It is for local testing only:

- Rooms live in memory (`InMemoryRelayStore`): a restart empties them.
- Any origin may connect.

## What to look at

- `lib/src/host.dart` — the `RelaySessionHost`, with the awareness plugin
  the client's shared cursors need.
- `main.dart` — `init()` starts the host and disposes it on `SIGINT`/`SIGTERM`.
- `routes/room/[id].dart` — the upgrade. The host reads the room from the
  client's hello frame, so the path id is unused.
