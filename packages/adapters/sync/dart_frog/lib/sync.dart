/// Server–client mode of `crdt_socket_sync` on a Dart Frog backend.
///
/// The HTTP server stays Dart Frog's; each upgraded socket is handed to a
/// [DocumentSessionHost], which holds the documents and takes the aligned
/// snapshots.
library;

export 'package:crdt_socket_sync/server.dart'
    show
        CRDTServerRegistry,
        DocumentSessionHost,
        SessionHostServer,
        SessionHostState,
        WebSocketChannelConnection;

export 'src/sync/handler.dart';
export 'src/sync/provider.dart';
