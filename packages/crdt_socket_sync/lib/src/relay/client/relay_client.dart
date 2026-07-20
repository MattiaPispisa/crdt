import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/client.dart';

/// Interface for a relay client.
///
/// A relay client syncs a [CRDTDocument] through a relay server that never
/// interprets CRDT data: the relay persists and rebroadcasts opaque change
/// blobs, and merging happens entirely on the clients.
///
/// Deviations from the [CRDTSocketClient] contract:
///
/// - [CRDTSocketClient.sendChange] enqueues the change and delivers it
///   at-least-once: the change leaves the queue only when the relay
///   acknowledges it. Local document changes are enqueued automatically.
/// - [CRDTSocketClient.requestSync] asks the relay for the persisted room
///   state, which is merged into the document (`merge: true`).
/// - [CRDTSocketClient.sessionId] is assigned by the relay on join and is
///   `null` while disconnected.
abstract class RelaySocketClient extends CRDTSocketClient {
  /// Constructor
  RelaySocketClient({super.plugins});

  /// Number of local change blobs not yet acknowledged by the relay.
  int get pendingChangesCount;

  /// The last relay log sequence number this client knows to have fully
  /// imported (`0` before the first welcome).
  int get lastKnownSeq;
}
