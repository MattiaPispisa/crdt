/// Dart Frog adapter for `crdt_socket_sync`.
///
/// Serves the CRDT sync and relay protocols from a Dart Frog backend: the
/// HTTP server stays Dart Frog's, and each upgraded socket is handed to a
/// `DocumentSessionHost` or a `RelaySessionHost` from `crdt_socket_sync`.
library;

export 'package:crdt_socket_sync/relay_server.dart'
    show RelayCompactionCoordinator, RelaySessionHost, RelayStore;
export 'package:crdt_socket_sync/server.dart'
    show
        CRDTServerRegistry,
        DocumentSessionHost,
        SessionHostServer,
        SessionHostState,
        WebSocketChannelConnection;

export 'src/handlers.dart';
export 'src/provider.dart';
