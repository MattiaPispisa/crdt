## [Unreleased](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.8.0/packages/crdt_socket_sync)

**Date:** --

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.7.0...crdt_socket_sync-v0.8.0)

### Fixed

- **A relay client now catches the relay up after a restart.** A welcome carries the whole room,
  so its version vector is exactly what the relay holds; whatever the document holds beyond that
  is pushed. Before, a change written while offline came back from storage as an *imported*
  change, never as a local one, and nothing pushed it — it stayed on that device for good. This is
  the same reconciliation the server-client mode already did at handshake, so an offline-first
  client only has to persist its document, with `crdt_lf_persistence`, and open the persistence
  before `connect()`.
  It also heals a room the relay lost: a change of another peer the relay no longer holds is
  pushed by whoever still has it.

### Changed

- `RelayPendingQueue` holds `Change`s and encodes them at push time, instead of encoding on the
  way in. A client writing while offline no longer pays for a push that is not happening. It also
  skips a change already waiting, so the reconciliation above never queues one twice.

- Requires `crdt_lf: ^4.2.0`.

## [0.7.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.7.0/packages/crdt_socket_sync)

**Date:** 2026-08-16

- Requires `crdt_lf: ^4.0.0` instead of `>=3.0.0 <5.0.0`. 
- The Dart floor moves to `>=3.0.0`, which `crdt_lf` now needs.

## [0.6.1](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.6.1/packages/crdt_socket_sync)

**Date:** 2026-07-28

Widens the `crdt_lf` constraint to `>=3.0.0 <5.0.0`. No functional changes, and no migration of existing databases.

## [0.6.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.6.0/packages/crdt_socket_sync)

**Date:** 2026-07-26

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.5.0+2...crdt_socket_sync-v0.6.0)

**Breaking changes (Dart names only — not the protocol)**

The CRDT-aware sync frames and session-event values now live under `Sync*`
types. These are pure **source-level renames**: update the identifiers, **the
on-the-wire messages stay byte-identical** (a `0.5.x` and a `0.6.0` peer still talk to
each other).

Messages:

- ~~`Message.change`~~ → **`SyncMessage.change`**
- ~~`Message.changes`~~ → **`SyncMessage.changes`**
- ~~`Message.documentStatus`~~ → **`SyncMessage.documentStatus`**
- ~~`Message.documentStatusRequest`~~ → **`SyncMessage.documentStatusRequest`**
- `Message.fromJson` now decodes only the shared frames (ping/pong/error); in a
  custom codec chain it: `SyncMessage.fromJson(json) ?? Message.fromJson(json)`.

Session events:

- ~~`SessionEventType.handshakeCompleted`~~ → **`SyncSessionEventType.handshakeCompleted`**
- ~~`SessionEventType.documentStatusCreated`~~ → **`SyncSessionEventType.documentStatusCreated`**
- ~~`SessionEventType.changeApplied`~~ → **`SyncSessionEventType.changeApplied`**
- ~~`SessionEventType.clientOutOfSync`~~ → **`SyncSessionEventType.clientOutOfSync`**

### Added

- **Relay mode** — a second sync model where the server stays *dumb*: it only
  stores change blobs opaquely and rebroadcasts them per room, never parsing
  CRDT data, so all merging happens on the clients. This enables a
  CRDT-agnostic backend (no `crdt_lf` on the server, easy to port to other
  runtimes, including serverless). Adds the `relay_client`,
  `web_socket_relay_client`, `relay_server` and `web_socket_relay_server`
  libraries; see the README for the full picture. [100](https://github.com/MattiaPispisa/crdt/issues/100)

### Fixed

- The client libraries now actually export `ClientSyncPlugin` and
  `SocketClientProvider` (the plugin barrel previously self-exported, forcing
  `src/` imports for custom client plugins).

## [0.5.0+2](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.5.0+2/packages/crdt_socket_sync)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.5.0`.

## [0.5.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.5.0+1/packages/crdt_socket_sync)

**Date:** 2026-07-18

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.5.0`.

## [0.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.5.0/packages/crdt_socket_sync)
**Date:** 2026-07-08

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.4.0...crdt_socket_sync-v0.5.0)

This release is a general pass to improve the sync process and clean up the
code following the improvements introduced in `crdt_lf` v3.0.0
(see [#87](https://github.com/MattiaPispisa/crdt/issues/87)).

### Added

- Client-side dead-connection detection: the client tracks pong replies and, if
  no pong arrives within `Protocol.pingTimeout`, treats the connection as dead
  and reconnects. Ping/pong durations are injectable via the `WebSocketClient`
  constructors.
- Backpressure: outbound sends are serialized through a bounded per-connection
  queue. A peer that exceeds `Protocol.maxBufferSize` of un-flushed data is
  disconnected (and re-syncs on reconnect) instead of growing memory without
  bound. The bound is injectable on both `WebSocketClient` and `WebSocketServer`.
- Server auto-snapshot: clients report their version vector on pings, and the
  server takes a snapshot and prunes confirmed history once every connected
  client has confirmed a common frontier (`ServerEventType.snapshotCreated`).
- `PingMessage` gained an optional `versionVector` field. This is
  backward-compatible on the wire (older peers ignore the extra field).

### Fixed

- `WebSocketServer.stop()` now actually closes every client session (previously a
  method tear-off meant sessions were never gracefully closed).
- A broadcast no longer aborts when a single client's send fails: the failing
  client is dropped and the message still reaches every other subscribed client.
- Incoming client frames are decoded per-frame instead of through a shared
  buffer, so a single malformed/undecodable frame can no longer poison the
  decoding of every subsequent message.
- Text frames are decoded with UTF-8 on both client and server (previously the
  client used `codeUnits`, corrupting multi-byte payloads).
- `InMemoryCRDTServerRegistry`: The server's out-of-sync recovery path is no longer dead code:
  `InMemoryCRDTServerRegistry.applyChange` now propagates
  `CausallyNotReadyException` so the server tells the client to re-sync instead
  of silently dropping the change.
- The awareness client no longer clobbers its own just-updated presence when a
  full state message arrives from the server.
- The awareness throttler now fires the trailing action in a burst (the last
  cursor position is no longer dropped).

## [0.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.4.0/packages/crdt_socket_sync)
**Date:** 2026-06-11

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.3.0...crdt_socket_sync-v0.4.0)

**Breaking changes**

Wire protocol changed: `Change`, `Snapshot`, and `VersionVector` payloads are now transmitted as base64-encoded binary strings instead of JSON objects. Servers and clients running different versions are not compatible.

Affected message fields:
- `HandshakeRequestMessage.versionVector` — was `Map<String, dynamic>`, now a base64 string.
- `HandshakeResponseMessage.versionVector`, `.snapshot`, `.changes[*]` — same change.
- `ChangeMessage.change` — was `Map<String, dynamic>`, now a base64 string.
- `ChangesMessage.changes[*]` — was `List<Map>`, now `List<String>` (base64).
- `DocumentStatusMessage.versionVector`, `.snapshot`, `.changes[*]` — same change.
- `DocumentStatusRequestMessage.versionVector` — same change.

Updated `crdt_lf` dependency to `^3.0.0`.

### Changed

- All binary payloads in messages now use the compact binary format from `crdt_lf` 3.0.0 (`Change.toBytes`, `VersionVector.toBytes`, `Snapshot.toBytes`), reducing message size and eliminating JSON parsing overhead on the hot path.
- chore: improved documentation adding design diagrams
- chore: update tests

## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.3.0/packages/crdt_socket_sync)
**Date:** 

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.2.0...crdt_socket_sync-v0.3.0)

**Breaking changes**
- `CRDTServerRegistry.addDocument` takes a `documentId` and `author` parameter
- `CRDTServerRegistry` methods now return a `Future`
- rename client `requestSnapshot` to `requestSync`

### Added
- Feature: add `messageCodec` parameter to `WebSocketServer` and `WebSocketClient`
- Feature: `JsonMessageCodec` now supports `toEncodable` and `reviver` parameters
- Feature: added out of sync error handling
- Feature: added `messageBroadcasted` and `messageSent` server events
- Feature: added `ChangesMessage`

### Changes
- Document status request can be sent without a version vector
- chore: added code coverage references

### Fixed 
- Fixed sync problems during client disconnection
- Fixed transporter subscription on connection error
- Fixed double call on "onNewSession"

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.2.0/packages/crdt_socket_sync)
**Date:** 2025-06-26

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.1.0...crdt_socket_sync-v0.2.0)

**Breaking changes**
- `encode` and `decode` methods of `MessageCodec` have nullable return type

### Added
- Feature: add plugin system
- Feature: add awareness plugin

### Fixed
- Fixed: Fix a missing status update during first connection
- Fixed: Fix a bug where the `connect` start a reconnection loop if the connection is lost

## [0.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.1.0+1/packages/crdt_socket_sync)
**Date:** 2025-06-14

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.1.0...crdt_socket_sync-v0.1.0+1)


### Fixed
- Chore: update readme links

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.1.0/packages/crdt_socket_sync)
**Date:** 2025-06-14

**Initial release**
