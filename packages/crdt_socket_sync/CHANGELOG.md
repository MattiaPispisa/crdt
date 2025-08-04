## [0.3.0]

**Breaking changes**
- `CRDTServerRegistry.addDocument` now only takes a `documentId` parameter
- `CRDTServerRegistry` methods now return a `Future`

### Added
- Feature: add `messageCodec` parameter to `WebSocketServer` and `WebSocketClient`
- Feature: `JsonMessageCodec` now supports `toEncodable` and `reviver` parameters

## [0.2.0] - 2025-06-26

**Breaking changes**
- `encode` and `decode` methods of `MessageCodec` have nullable return type

### Added
- Feature: add plugin system
- Feature: add awareness plugin

### Fixed
- Fixed: Fix a missing status update during first connection
- Fixed: Fix a bug where the `connect` start a reconnection loop if the connection is lost

## [0.1.0+1] - 2025-06-14

### Fixed
- Chore: update readme links

## [0.1.0] - 2025-06-14

- Initial release
