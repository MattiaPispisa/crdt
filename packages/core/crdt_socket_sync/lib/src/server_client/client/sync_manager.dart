import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';

/// {@template sync_manager}
/// Keeps a [CRDTDocument] and a [CRDTSocketClient] in step.
///
/// It sends what the document writes locally, and applies what the server
/// sends back.
/// {@endtemplate}
class SyncManager {
  /// {@macro sync_manager}
  ///
  /// Subscribes to [CRDTDocument.localChanges] at once; [dispose] ends it.
  SyncManager({
    required this.document,
    required this.client,
  }) {
    // Listen to the local changes and send them to the server
    _localChangesSubscription =
        document.localChanges.listen(_handleLocalChange);
  }

  /// The local CRDT document
  final CRDTDocument document;

  /// The socket client
  final CRDTSocketClient client;

  /// Subscription to the local changes stream
  StreamSubscription<Change>? _localChangesSubscription;

  /// Handles a local change
  Future<void> _handleLocalChange(Change change) async {
    // Send the change to the server
    await tryCatchIgnore(() async {
      await client.sendMessage(
        SyncMessage.change(
          documentId: document.documentId,
          change: change,
        ),
      );
    });
  }

  /// Sends a list of changes to the server
  Future<void> _sendChangesToServer(List<Change> changes) async {
    await tryCatchIgnore(() async {
      await client.sendMessage(
        SyncMessage.changes(
          documentId: document.documentId,
          changes: changes,
        ),
      );
    });
  }

  /// Applies a change
  ///
  /// {@template sync_manager_apply_failure}
  /// A causal gap is the one failure a resync can close, so it is the only one
  /// answered with [requestDocumentStatus]: re-serving the same document would
  /// fail the same way for any other reason, and asking again is a loop rather
  /// than a recovery.
  ///
  /// Anything else becomes a [SyncFault].
  /// {@macro sync_fault_not_thrown}
  /// {@endtemplate}
  void applyChange(Change change) {
    if (_applyOne(change)) {
      requestDocumentStatus();
    }
  }

  /// Applies [change], and says whether it left a causal gap.
  ///
  /// {@macro sync_manager_apply_failure}
  bool _applyOne(Change change) {
    try {
      document.applyChange(change);
    } on CausallyNotReadyException {
      return true;
    } on MissingDependencyException {
      return true;
    } catch (error, stackTrace) {
      _reportApplyFailure(change, error, stackTrace);
    }
    return false;
  }

  /// Reports a failure that no resync can fix, naming the change it was on.
  void _reportApplyFailure(Change change, Object error, StackTrace stackTrace) {
    client.reportSyncFault(
      SyncFault(
        reason: 'Could not apply change ${change.id} from the server',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Applies a list of changes.
  ///
  /// Every change is tried, so one the document refuses does not hold back
  /// the ones behind it. One status request covers the whole batch.
  ///
  /// {@macro sync_manager_apply_failure}
  void applyChanges(List<Change> changes) {
    var gap = false;
    for (final change in changes) {
      gap |= _applyOne(change);
    }

    if (gap) {
      requestDocumentStatus();
    }
  }

  /// [CRDTDocument.import] with:
  /// - `merge: false`
  /// - `pruneHistory: true`
  ///
  /// Returns whether the state went in. On `false` nothing is sent back: this
  /// peer never took the server's state, so what it holds is not an answer.
  ///
  /// A failure becomes a [SyncFault].
  /// {@macro sync_fault_not_thrown}
  bool import({
    required VersionVector serverVersionVector,
    List<Change>? changes,
    Snapshot? snapshot,
  }) {
    try {
      document.import(
        changes: changes,
        snapshot: snapshot,
      );
    } catch (error, stackTrace) {
      client.reportSyncFault(
        SyncFault(
          reason: 'Could not import the state the server served',
          error: error,
          stackTrace: stackTrace,
        ),
      );
      return false;
    }

    _sendUnknownChangesToServerSync(
      document.exportChangesNewerThan(serverVersionVector),
    );
    return true;
  }

  /// Send a list of changes that were already exported (synchronous version)
  void _sendUnknownChangesToServerSync(List<Change> changes) {
    if (changes.isEmpty) {
      return;
    }

    // Use unawaited because we can't await in merge (it's not async)
    unawaited(_sendChangesToServer(changes));
  }

  /// Requests the document status from the server
  Future<void> requestDocumentStatus() async {
    await tryCatchIgnore(() {
      // Request a snapshot from the server
      return client.sendMessage(
        SyncMessage.documentStatusRequest(
          documentId: document.documentId,
          versionVector: document.getVersionVector(),
        ),
      );
    });
  }

  /// Dispose the resources
  void dispose() {
    _localChangesSubscription?.cancel();
    _localChangesSubscription = null;
  }
}
