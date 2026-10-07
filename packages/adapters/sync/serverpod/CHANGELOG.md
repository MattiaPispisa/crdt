## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync_serverpod-v0.1.0/packages/adapters/sync/serverpod)

**Date:** 2026-10-07

### Initial Release

- Serve `crdt_socket_sync` from a [Serverpod](https://pub.dev/packages/serverpod)
  web server: `CrdtSyncRoute` (`sync.dart`) and `CrdtRelayRoute` (`relay.dart`)
  upgrade the request and hand the socket to the session host.
- Refuse a connection with a normal HTTP status before the upgrade: subclass the
  route, check the request or the `Session`, then call `super.handleCall`.
- `RelicWebSocketConnection`: a `TransportConnection` over a Relic WebSocket.
