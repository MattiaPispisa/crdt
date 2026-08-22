/// Relay server library for CRDT Socket Sync.
///
/// A relay server rebroadcasts opaque CRDT change blobs to the other clients
/// of a room and persists them in a `RelayStore`, without ever interpreting
/// CRDT data: merging is entirely a client concern.
library;

export 'src/common/common/common.dart';
export 'src/common/server/client_session.dart';
export 'src/common/server/client_session_event.dart';
export 'src/common/server/event.dart';
export 'src/common/server/server.dart';
export 'src/plugins/server.dart';
export 'src/relay/common/common.dart';
export 'src/relay/server/compaction.dart';
export 'src/relay/server/in_memory_relay_store.dart';
export 'src/relay/server/relay_client_session.dart';
export 'src/relay/server/relay_session_event.dart';
export 'src/relay/server/store.dart';
