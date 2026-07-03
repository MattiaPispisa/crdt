## [0.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync-v0.5.0/packages/crdt_socket_sync)
**Date:** 2026-07-03

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_socket_sync-v0.4.0...crdt_socket_sync-v0.5.0)

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
