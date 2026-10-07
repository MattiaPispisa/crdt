## [0.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync_dart_frog-v0.1.0+1/packages/adapters/sync/dart_frog)

**Date:** --

- Documentation release: refreshes the README published on pub.dev. No functional changes since `0.1.0`.

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync_dart_frog-v0.1.0/packages/adapters/sync/dart_frog)

**Date:** 2026-10-04

### Initial Release

Serve `crdt_socket_sync` from a [Dart Frog](https://pub.dev/packages/dart_frog)
backend, one library per mode. `sync.dart`: `crdtSyncWebSocketHandler` upgrades
a route's request and hands the socket to a `DocumentSessionHost`,
`crdtSyncHostProvider` puts the host where `context.read` will find it.
`relay.dart`: the same two for a `RelaySessionHost`.

Because the upgrade happens inside a route, the request — headers, cookies,
whatever middleware put in the context — is available before the socket exists,
so a connection can be authenticated and turned away with an ordinary
`Response` rather than refused after the handshake.
