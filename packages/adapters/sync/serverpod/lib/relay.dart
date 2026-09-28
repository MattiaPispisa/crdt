/// Relay mode of `crdt_socket_sync` on a Serverpod web server.
///
/// The HTTP server stays Serverpod's; each upgraded socket is handed to a
/// [RelaySessionHost], which rebroadcasts opaque change blobs per room and
/// never interprets CRDT data.
library;

import 'package:crdt_socket_sync/relay_server.dart';

export 'package:crdt_socket_sync/relay_server.dart'
    show
        RelayCompactionCoordinator,
        RelaySessionHost,
        RelayStore,
        SessionHostServer,
        SessionHostState;

export 'src/common/relic_web_socket_connection.dart';
export 'src/relay/route.dart';
