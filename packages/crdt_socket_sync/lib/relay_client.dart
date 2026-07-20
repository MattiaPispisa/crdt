/// Relay client library for CRDT Socket Sync.
///
/// A relay client syncs a document through a relay server that never
/// interprets CRDT data (see `relay_server.dart`): the relay persists and
/// rebroadcasts opaque change blobs, and merging happens entirely on the
/// clients.
library crdt_socket_sync_relay_client;

export 'src/common/client/status.dart';
export 'src/common/common/common.dart';
export 'src/plugins/client.dart';
export 'src/relay/client/relay_client.dart';
export 'src/relay/client/relay_sync_manager.dart';
export 'src/relay/common/common.dart';
