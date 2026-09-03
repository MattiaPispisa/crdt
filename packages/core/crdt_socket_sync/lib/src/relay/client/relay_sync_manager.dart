import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/relay/client/pending_queue.dart';
import 'package:crdt_socket_sync/src/relay/client/relay_client.dart';
import 'package:crdt_socket_sync/src/relay/client/seq_tracker.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';

/// {@template relay_sync_manager}
/// Manager for a relay client.
///
/// It is responsible for:
/// - enqueueing local [document] changes and pushing them to the relay
///   with at-least-once delivery ([RelayPendingQueue])
/// - importing the room state served by the relay (welcome) and the
///   rebroadcast changes of other clients
/// - answering compaction requests with a snapshot upload that never
///   covers log entries this client has not imported ([RelaySeqTracker])
/// {@endtemplate}
class RelaySyncManager {
  /// {@macro relay_sync_manager}
  ///
  /// Constructor
  RelaySyncManager({
    required this.document,
    required this.client,
  })  : _queue = RelayPendingQueue(),
        _seqTracker = RelaySeqTracker() {
    // Listen to the local changes and enqueue them for the relay
    _localChangesSubscription = document.localChanges.listen(enqueue);
  }

  /// The local CRDT document
  final CRDTDocument document;

  /// The relay client
  final RelaySocketClient client;

  /// The at-least-once outbound queue
  final RelayPendingQueue _queue;

  /// Which prefix of the room log this client has imported
  final RelaySeqTracker _seqTracker;

  /// Whether a welcome was received on the current connection
  bool _handshaken = false;

  /// Subscription to the local changes stream
  StreamSubscription<Change>? _localChangesSubscription;

  /// Number of local change blobs not yet acknowledged by the relay.
  int get pendingChangesCount => _queue.length;

  /// The last relay log sequence number this client knows to have fully
  /// imported (`0` before the first welcome).
  int get lastKnownSeq => _seqTracker.maxContiguous;

  /// The local changes not yet acknowledged by the relay, oldest first.
  ///
  /// {@template relay_pending_changes}
  /// Write these down to carry at-least-once delivery across a restart, and
  /// hand them back with [restorePendingChanges] before connecting. Without
  /// that, a change written while offline comes back from storage as an
  /// imported change, never as a local one, so nothing ever pushes it.
  /// {@endtemplate}
  List<Change> get pendingChanges => _queue.pending;

  /// Seeds the queue with [changes] a previous session left unacknowledged.
  ///
  /// {@macro relay_pending_changes}
  ///
  /// Changes already queued are skipped. Call before connecting: nothing is
  /// pushed until a welcome arrives.
  void restorePendingChanges(Iterable<Change> changes) {
    _queue.restore(changes);
  }

  /// Enqueues [change] for the relay and flushes.
  void enqueue(Change change) {
    _queue.add(change);
    unawaited(flush());
  }

  /// Imports the room state of a welcome.
  ///
  /// The state is merged (`merge: true`) into the document: on a reconnect
  /// the document already holds local state that must not be clobbered.
  /// History is kept (`pruneHistory: false`) so this client can later
  /// upload a snapshot covering it.
  ///
  /// Unacknowledged local changes survived the reconnect in the queue and
  /// are re-pushed; peers de-duplicate re-delivered changes.
  Future<void> onWelcome(RelayWelcomeMessage message) async {
    document.import(
      snapshot: message.snapshot != null
          ? Snapshot.fromBytes(base64Decode(message.snapshot!))
          : null,
      changes: [
        for (final blob in message.changes)
          Change.fromBytes(base64Decode(blob)),
      ],
      merge: true,
      pruneHistory: false,
    );

    _seqTracker.markThrough(message.seq);
    _handshaken = true;
    _queue.resetInFlight();

    await flush();

    if (message.compact) {
      await uploadSnapshot(message.seq);
    }
  }

  /// Handles the ack of a push: drops the acknowledged blobs and flushes
  /// what queued up in the meantime.
  Future<void> onAck(RelayAckMessage message) async {
    _seqTracker.addRange(from: message.seq - message.count, to: message.seq);
    _queue.ack(message.count);

    await flush();

    if (message.compact) {
      await uploadSnapshot(message.seq);
    }
  }

  /// Imports change blobs rebroadcast by the relay.
  ///
  /// [CRDTDocument.importChanges] de-duplicates, so re-delivered blobs are
  /// harmless.
  void onChanges(RelayChangesMessage message) {
    document.importChanges([
      for (final blob in message.changes) Change.fromBytes(base64Decode(blob)),
    ]);
    _seqTracker.addRange(
      from: message.seq - message.changes.length,
      to: message.seq,
    );
  }

  /// Marks the connection as lost.
  ///
  /// The queue keeps the unacknowledged blobs (in-flight included): they are
  /// re-pushed after the next welcome.
  void onConnectionLost() {
    _handshaken = false;
    _queue.resetInFlight();
  }

  /// Pushes every queued blob, if allowed.
  ///
  /// A push is sent only when a welcome was received on the current
  /// connection and no other push is in flight (acks pair with pushes
  /// one-to-one).
  Future<void> flush() async {
    if (!_handshaken || _queue.hasInFlight || _queue.isEmpty) {
      return;
    }

    final changes = _queue.takeInFlight();
    try {
      await client.sendMessage(
        RelayPushMessage(
          documentId: document.documentId,
          changes: [
            for (final change in changes) base64Encode(change.toBytes()),
          ],
        ),
      );
    } catch (_) {
      // The push did not go out: return the window to the pending state so
      // the blobs are re-pushed after the reconnect welcome.
      _queue.resetInFlight();
    }
  }

  /// Uploads a snapshot to compact the room log.
  ///
  /// [requestedSeq] is the log position the relay asked to compact. The
  /// upload covers at most [lastKnownSeq]: covering log entries this client
  /// has not imported would lose them for future joiners once the relay
  /// truncates the log.
  Future<void> uploadSnapshot(int requestedSeq) async {
    final upToSeq = requestedSeq < lastKnownSeq ? requestedSeq : lastKnownSeq;
    if (upToSeq <= 0) {
      return;
    }

    await tryCatchIgnore(() async {
      final snapshot = document.takeSnapshot(pruneHistory: false);
      await client.sendMessage(
        RelaySnapshotUploadMessage(
          documentId: document.documentId,
          snapshot: base64Encode(snapshot.toBytes()),
          upToSeq: upToSeq,
        ),
      );
    });
  }

  /// Sends a state request; the relay answers with a welcome carrying the
  /// current persisted room state.
  Future<void> requestState() async {
    await tryCatchIgnore(() {
      return client.sendMessage(
        RelayStateRequestMessage(documentId: document.documentId),
      );
    });
  }

  /// Dispose the resources
  void dispose() {
    _localChangesSubscription?.cancel();
    _localChangesSubscription = null;
  }
}
