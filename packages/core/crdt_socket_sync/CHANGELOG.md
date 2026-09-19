## [0.9.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.9.0/packages/core/crdt_socket_sync)

**Date:** 2026-09-18

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.8.0...crdt_socket_sync-v0.9.0)

### Breaking

Needs `crdt_lf: ^5.0.0`. A 0.8.0 peer still connects: both new handshake fields are optional on
read. See [Migrating from 0.8.x to 0.9.0](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/crdt_socket_sync#migrating-from-08x-to-090).

- `Protocol.version` (the string `'1.0.0'`) is replaced by `Protocol.protocolVersion`, an `int`.
- `ConnectionStatus` has a new value, `unsupported`, so an exhaustive `switch` needs another case.
- A `CRDTSocketClient` subclass no longer provides `connectionStatus`,
  `connectionStatusValue` or a status controller of its own: the base class owns
  them, and a transport only calls `updateConnectionStatus`.
- `PluginAwareMessageCodec` takes the protocol's codec and the plugins' codecs
  apart (`PluginAwareMessageCodec(defaultCodec: ..., pluginCodecs: ...)`)
  instead of one flat list. `fromPlugins` is unchanged.

### Added

- **An incompatible client is refused at the handshake instead of failing later.** Both peers state
  the protocol version they speak, and the client states what its build can read
  (`DocumentCapabilities`). The server compares that with what the document's data asks for
  (`DocumentRequirements`), answers `UNSUPPORTED_PROTOCOL_VERSION` or `UNSUPPORTED_CLIENT`, and
  closes. Snapshot blob layouts are compared as a range per handler type, so a build that reads an
  older layout is not refused; `SnapshotBlobTooNew` and `SnapshotBlobTooOld` say which way it failed.
  The client latches the refusal in the terminal `ConnectionStatus.unsupported` and exposes it on
  `CRDTSocketClient.incompatibility`. A relay checks the version only.
  [142](https://github.com/MattiaPispisa/crdt/issues/142)

### Changed

- **What the client cannot apply is reported on the new `CRDTSocketClient.faults`, not thrown.**
  Applying runs inside the socket's read callback, where a throw became an uncaught zone error.
  Only a causal gap still triggers `requestDocumentStatus()`; re-serving the document cannot fix
  anything else. `faults` replays nothing, so `CRDTSocketClient.lastFault` holds the last one for
  a listener that subscribed late.

- **A frame the server cannot read is answered with `INVALID_MESSAGE`.** One that threw on the way
  in used to be logged and nothing more, leaving the client waiting for a reply that never came.

### Fixed

- **A plugin's codec now writes the plugin's messages.** It only took part in decoding before: the
  protocol's codec answered for every message, so a plugin whose codec is not the default JSON —
  binary, an envelope, encrypted — put the wrong bytes on the wire and the peer refused them. A
  message from `MessageTypeValue.firstPluginValue` up now goes to the plugins' codecs, anything
  below to the protocol's.

- **A codec that throws no longer hides the ones after it.** Handed a frame it was not written for,
  a codec can throw instead of declining, and that ended the search — so adding a plugin could stop
  an existing one's messages from being read.

- **A transport says when the peer closes it.** A clean close left no trace: the next frame opened a
  second socket behind the client's back, one that never handshakes, so the client looked connected
  and every change it sent was dropped by the server in silence. The close is now reported on
  `Transport.incoming`, which is what drives the reconnect, and sending on a closed transport throws.

- **A session closes its socket however it ends.** Only `close()` did, so a client dropped for a
  heartbeat timeout — or for a transport error, or a failed send — left its socket and its incoming
  subscription alive for the life of the process.

- **A client no longer throws in debug on a frame it was not meant to read.** A frame from a plugin
  it does not have, or bytes with no readable type, are dropped the way the server drops them.

## [0.8.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.8.0/packages/core/crdt_socket_sync)

**Date:** 2026-09-07

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.7.0...crdt_socket_sync-v0.8.0)

### Added

- **`PersistentServerRegistry`**: a `CRDTServerRegistry` that keeps every document it serves on disk.
  It takes any `CRDTStorageBackend` — `CRDTHive`, `CRDTDrift` or `CRDTSqlite` — and gives each
  document a `CRDTDocumentPersistence`, so writes are batched, a snapshot replaces the one before it,
  and a prune drops exactly what it covered. Documents open lazily, `compactAfter` snapshots one once
  its log gets long, and the `snapshots` stream is how a server learns to broadcast the new status.

- **`PersistentServerRegistry.releaseDocument`**, and the `idleAfter` that calls it on a timer: the
  other half of the lazy open. It writes what the document holds, closes it, and leaves the id in the
  catalog — the room is still served, and the next `getDocument` reads it back. Without it a server
  holds every room it has ever served.

- **`ServerDocumentCatalog`**, with `BackendDocumentCatalog` and `InMemoryServerDocumentCatalog`: what
  answers `documentIds`, `hasDocument` and `documentCount`. The default asks the backend, so the
  server keeps no second list and finds its documents again after a restart — which also makes
  `removeDocument` a delete rather than a forget; use `releaseDocument` for that.
  `InMemoryServerDocumentCatalog` is for a server that should start empty every time.

### Fixed

- **A relay client now catches the relay up after a restart.** A change written while offline came
  back from storage as an imported change, never as a local one, so nothing pushed it and it stayed
  on that device for good. The welcome's version vector is now reconciled against the document, as
  the server-client mode already did at handshake — so an offline-first client only has to open its
  persistence before `connect()`. It also heals a room the relay lost.

- **A server shutdown writes what its clients had already sent.** `WebSocketServer.dispose` disposed
  each document by hand, which on a durable registry read every document back into memory, never
  flushed the pending writes, and left the registry holding disposed documents. `CRDTServerRegistry`
  now has a `close()`, no-op by default, and `dispose` calls that instead.

- **`RelaySyncManager.dispose` stops the pushes.** A `flush` already in flight could still write to a
  client that was closing.

### Changed

- `RelayPendingQueue` holds `Change`s and encodes them at push time, so a client writing while
  offline no longer pays for a push that is not happening. It also skips a change already waiting.

- Requires `crdt_lf: ^4.2.0`, and now depends on `crdt_lf_persistence` — the storage contract only, so
  the sync is still tied to no backend.

## [0.7.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.7.0/packages/core/crdt_socket_sync)

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
