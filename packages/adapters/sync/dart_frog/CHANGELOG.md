## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_socket_sync_dart_frog-v0.1.0/packages/adapters/sync/dart_frog)

**Date:** 2026-09-20

### Initial Release

Serve `crdt_socket_sync` from a [Dart Frog](https://pub.dev/packages/dart_frog)
backend. `crdtSyncWebSocketHandler` and `crdtRelayWebSocketHandler` upgrade a
route's request and hand the socket to a `DocumentSessionHost` or a
`RelaySessionHost`; `crdtSyncHostProvider` and `crdtRelayHostProvider` put the
host where `context.read` will find it.

Because the upgrade happens inside a route, the request — headers, cookies,
whatever middleware put in the context — is available before the socket exists,
so a connection can be authenticated and turned away with an ordinary
`Response` rather than refused after the handshake.
