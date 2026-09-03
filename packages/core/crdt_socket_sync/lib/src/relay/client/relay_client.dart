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

  /// Number of local changes not yet acknowledged by the relay.
  int get pendingChangesCount;

  /// The local changes not yet acknowledged by the relay, oldest first.
  ///
  /// {@template relay_client_pending_changes}
  /// At-least-once delivery holds for as long as this client lives. To keep it
  /// across a restart, write these down and hand them back with
  /// [restorePendingChanges] before connecting: a change written while offline
  /// comes back from storage as an imported change, never as a local one, so
  /// nothing else would ever push it.
  /// {@endtemplate}
  List<Change> get pendingChanges;

  /// Seeds the queue with [changes] a previous session left unacknowledged.
  ///
  /// {@macro relay_client_pending_changes}
  ///
  /// Changes already queued are skipped, so calling it twice is harmless.
  void restorePendingChanges(Iterable<Change> changes);

  /// The last relay log sequence number this client knows to have fully
  /// imported (`0` before the first welcome).
  int get lastKnownSeq;
}
