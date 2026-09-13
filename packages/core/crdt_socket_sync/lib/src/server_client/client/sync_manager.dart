import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';

/// {@template sync_manager}
/// Manager for the CRDT client
///
/// it's responsible for:
/// - implementing the requested changes to the [document]
/// - submitting the changes to the [document]
/// {@endtemplate}
class SyncManager {
  /// {@macro sync_manager}
  ///
  /// Constructor
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
  /// Anything else is reported on [CRDTSocketClient.faults] and not thrown.
  /// This runs inside the callback that reads the socket, where a throw reaches
  /// no `catch` and no `onError` — it lands in the zone, which on Flutter is a
  /// crash instead of a message.
  /// {@endtemplate}
  void applyChange(Change change) {
    try {
      document.applyChange(change);
    } on CausallyNotReadyException {
      requestDocumentStatus();
    } on MissingDependencyException {
      requestDocumentStatus();
    } catch (error, stackTrace) {
      _reportApplyFailure(error, stackTrace, count: 1);
    }
  }

  /// Reports a failure that no resync can fix.
  void _reportApplyFailure(
    Object error,
    StackTrace stackTrace, {
    required int count,
  }) {
    client.reportSyncFault(
      SyncFault(
        reason: 'Could not apply $count change(s) from the server',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Applies a list of changes
  ///
  /// {@macro sync_manager_apply_failure}
  void applyChanges(List<Change> changes) {
    try {
      for (final change in changes) {
        document.applyChange(change);
      }
    } on CausallyNotReadyException {
      requestDocumentStatus();
    } on MissingDependencyException {
      requestDocumentStatus();
    } catch (error, stackTrace) {
      _reportApplyFailure(error, stackTrace, count: changes.length);
    }
  }

  /// [CRDTDocument.import] with:
  /// - `merge: false`
  /// - `pruneHistory: true`
  ///
  /// A failure is reported on [CRDTSocketClient.faults] rather than thrown,
  /// for the same reason [applyChange] does it: this runs inside the socket's
  /// read callback, where a throw would land in the zone. Nothing is sent back
  /// when the import fails — there is no state to report yet.
  void import({
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
      return;
    }

    _sendUnknownChangesToServerSync(
      document.exportChangesNewerThan(serverVersionVector),
    );
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
