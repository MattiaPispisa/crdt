/// Relay mode of `crdt_socket_sync` on a Dart Frog backend.
///
/// The HTTP server stays Dart Frog's; each upgraded socket is handed to a
/// [RelaySessionHost], which rebroadcasts opaque change blobs per room and
/// never interprets CRDT data.
library;

export 'package:crdt_socket_sync/relay_server.dart'
    show
        RelayCompactionCoordinator,
        RelaySessionHost,
        RelayStore,
        SessionHostServer,
        SessionHostState,
        WebSocketChannelConnection;

export 'src/relay/handler.dart';
export 'src/relay/provider.dart';
