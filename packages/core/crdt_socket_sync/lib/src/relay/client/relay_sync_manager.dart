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

  /// Enqueues [change] for the relay and flushes.
  void enqueue(Change change) {
    _queue.add(change);
    unawaited(flush());
  }

  /// Imports the room state of a welcome, then queues everything the relay
  /// does not hold.
  ///
  /// The state is merged (`merge: true`) into the document: on a reconnect
  /// the document already holds local state that must not be clobbered.
  /// History is kept (`pruneHistory: false`) so this client can later
  /// upload a snapshot covering it.
  ///
  /// A welcome carries the whole room — the snapshot plus the log after it —
  /// so its version vector is exactly what the relay has. Whatever the
  /// document holds beyond that is queued and pushed, whoever wrote it. That
  /// covers three cases with one rule: unacknowledged changes that survived
  /// the reconnect, changes restored from storage after a restart (which
  /// reach the document as imported ones, so nothing else would ever push
  /// them), and changes of another peer the relay lost.
  ///
  /// It is the same reconciliation the server-client mode does at handshake,
  /// and it inherits the same limit: a version vector cannot describe a hole
  /// in the middle of one peer's sequence, only how far that peer got.
  ///
  /// Re-delivering a change the relay already had is harmless: the relay
  /// appends it and every peer discards it as known.
  Future<void> onWelcome(RelayWelcomeMessage message) async {
    final snapshot = message.snapshot != null
        ? Snapshot.fromBytes(base64Decode(message.snapshot!))
        : null;
    final changes = [
      for (final blob in message.changes) Change.fromBytes(base64Decode(blob)),
    ];

    document.import(
      snapshot: snapshot,
      changes: changes,
      merge: true,
      pruneHistory: false,
    );

    _seqTracker.markThrough(message.seq);
    _handshaken = true;
    _queue.resetInFlight();

    _queueUnknownToRelay(snapshot, changes);

    await flush();

    if (message.compact) {
      await uploadSnapshot(message.seq);
    }
  }

  /// Queues every change the document holds that the welcome did not carry.
  void _queueUnknownToRelay(Snapshot? snapshot, List<Change> changes) {
    var relayVersion = VersionVector({});
    if (snapshot != null) {
      relayVersion = relayVersion.merged(snapshot.versionVector);
    }
    for (final change in changes) {
      relayVersion.update(change.id.peerId, change.id.hlc);
    }

    for (final change in document.exportChangesNewerThan(relayVersion)) {
      _queue.add(change);
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
