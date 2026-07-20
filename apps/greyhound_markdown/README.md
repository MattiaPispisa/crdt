# Greyhound Markdown

<div align="center">
  <img height="250" alt="Greyhound Markdown logo" src="https://raw.githubusercontent.com/MattiaPispisa/crdt/main/assets/images/greyhound_markdown_logo.png">
</div>

<div align="center">

[![Open the live demo](https://img.shields.io/badge/▶%20Open%20live%20demo-mattiapispisa.it%2Fcrdt%2Fgreyhound_markdown-2ea44f?style=for-the-badge&logo=flutter&logoColor=white)](https://mattiapispisa.it/crdt/greyhound_markdown/)

</div>

Real-time collaborative markdown editor built on
[`crdt_lf`](../../packages/crdt_lf),
[`crdt_lf_flutter`](../../packages/crdt_lf_flutter) and the **relay mode** of
[`crdt_socket_sync`](../../packages/crdt_socket_sync).

- `client/` — Flutter web app (editor + live preview, shared cursors). It
  uses the package's `WebSocketRelayClient` and `ClientAwarenessPlugin`
  directly; the room id is the CRDT `documentId`.
- `server/` — Cloudflare Worker + Durable Object acting as a relay server:
  it rebroadcasts opaque CRDT blobs to the other clients of a room and
  persists them (change log + compacted snapshots) in Durable Object
  storage. All CRDT merge happens client-side. It is a **TypeScript
  reference implementation of the `crdt_socket_sync` relay protocol** — the
  same contract `WebSocketRelayServer` implements in Dart.

## Architecture

```
Client A ──ws──┐
               ├── Worker GET /room/:id ──► RoomDO (idFromName; sessions,
Client B ──ws──┘                            DO storage: change log + snapshot)
```

Wire protocol: the `crdt_socket_sync` relay protocol (JSON envelopes typed by
integer codes, CRDT binary blobs as base64). The server (`server/src/`)
speaks hello/welcome, push/ack, changes, snapshotUpload/compaction, ping/pong
and awareness (100–102) — see
[Implementing a relay server](../../packages/crdt_socket_sync/README.md#implementing-a-relay-server)
for the message contract to keep in sync. The client has no hand-rolled
protocol: it drives `WebSocketRelayClient` from the package.

This app demonstrates that the relay server contract is host-agnostic: a
Cloudflare Worker serves the same package client that a Dart
`WebSocketRelayServer` would.

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

The e2e test drives two real `WebSocketRelayClient`s through the local worker
and checks convergence, awareness propagation and late-joiner catch-up.

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)
