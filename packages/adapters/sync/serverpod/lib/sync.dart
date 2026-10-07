/// Server–client mode of `crdt_socket_sync` on a Serverpod web server.
///
/// The HTTP server stays Serverpod's; each upgraded socket is handed to a
/// [DocumentSessionHost], which holds the documents and takes the aligned
/// snapshots.
library;

import 'package:crdt_socket_sync/server.dart';

export 'package:crdt_socket_sync/server.dart'
    show
        CRDTServerRegistry,
        DocumentSessionHost,
        SessionHostServer,
        SessionHostState;

export 'src/common/relic_web_socket_connection.dart';
export 'src/sync/route.dart';
