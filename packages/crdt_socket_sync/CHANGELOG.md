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
