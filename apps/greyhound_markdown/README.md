# Greyhound Markdown

Real-time collaborative markdown editor built on
[`crdt_lf`](../../packages/crdt_lf) and
[`crdt_lf_flutter`](../../packages/crdt_lf_flutter).

- `client/` — Flutter web app (editor + live preview, shared cursors).
- `server/` — Cloudflare Worker + Durable Object acting as a dumb relay:
  it rebroadcasts opaque CRDT blobs to the other clients of a room and
  persists them (change log + compacted snapshots) in Durable Object
  storage. All CRDT merge happens client-side.

## Architecture

```
Client A ──ws──┐
               ├── Worker GET /room/:id ──► RoomDO (idFromName; sessions,
Client B ──ws──┘                            DO storage: change log + snapshot)
```

Wire protocol: JSON text frames, CRDT binary blobs as base64. Message types:
`welcome`, `push`/`ack`, `change`, `snapshot` (log compaction), `awareness`
(ephemeral presence), `peer_left`. The Dart side lives in
`client/lib/src/model/protocol.dart`, the TypeScript side in
`server/src/protocol.ts` — keep them in sync.

`crdt_socket_sync` is intentionally **not** used: its client requires a
CRDT-aware server (handshake with server-computed deltas), which a dumb
relay cannot provide.

## Run it

Server (terminal 1):

```sh
cd server
npm install   # if sharp fails building from source because a global
              # libvips is installed: SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install
npx wrangler dev   # ws://localhost:8787, state persists in .wrangler/state
```

Client (terminals 2 and 3, from `client/`):

```sh
fvm flutter run -d chrome --web-port 5001
fvm flutter run -d chrome --web-port 5002
```

Create a room in one tab, copy the room id (toolbar button) and join it from
the other tab — or open `http://localhost:5002/#/room/<id>` directly.

Point the client at a deployed worker with
`--dart-define=GREYHOUND_WS=wss://your-worker.example.com`.

## Tests

```sh
cd client
fvm flutter test                                        # unit tests
fvm flutter test --dart-define=E2E=true test/e2e_test.dart  # needs wrangler dev
```

The e2e test drives two real `SyncClient`s through the local server and
checks convergence, awareness propagation and late-joiner catch-up.
