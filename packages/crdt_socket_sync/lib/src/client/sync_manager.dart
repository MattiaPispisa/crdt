import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/client/change_failures_handler.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';

/// Manager for the CRDT client
class SyncManager {
  /// Constructor
  SyncManager({
    required this.document,
    required this.client,
  }) : _failuresHandler = ChangeFailuresHandler(
          // setup the retry interval as the reconnect interval
          client: client,
          retryInterval: Protocol.reconnectInterval,
        ) {
    // Listen to the local changes and send them to the server
    _localChangesSubscription =
        document.localChanges.listen(_handleLocalChange);
  }

  /// The local CRDT document
  final CRDTDocument document;

  /// The document ID
  String get _documentId => document.peerId.toString();

  /// The changes that have not been sent to the server
  List<Change> get unSyncChanges => _failuresHandler.unSyncChanges;

  /// Stream of the number of unSyncChanges
  Stream<int> get unSyncChangesCount => _failuresHandler.unSyncChangesCount;

  /// The socket client
  final CRDTSocketClient client;

  final ChangeFailuresHandler _failuresHandler;

  /// Subscription to the local changes stream
  StreamSubscription<Change>? _localChangesSubscription;

  /// Handles a local change
  Future<void> _handleLocalChange(Change change) async {
    if (unSyncChanges.isNotEmpty) {
      _failuresHandler.add(change);
      return;
    }

    // Send the change to the server
    try {
      await client.sendMessage(
        Message.change(
          documentId: _documentId,
          change: change,
        ),
      );
    } catch (e) {
      _failuresHandler.add(change);
    }
  }

  /// Applies a change
  void applyChange(Change change) {
    try {
      document.applyChange(change);
    } catch (e) {
      _requestMissingChanges();
    }
  }

  /// Applies a list of changes
  void applyChanges(List<Change> changes) {
    try {
      for (final change in changes) {
        document.applyChange(change);
      }
    } catch (e) {
      _requestMissingChanges();
    }
  }

  /// Imports or merges changes and snapshot
  void importOrMerge({
    List<Change>? changes,
    Snapshot? snapshot,
  }) {
    final applied = document.import(
      changes: changes,
      snapshot: snapshot,
    );

    if (applied == -1) {
      document.import(
        changes: changes,
        snapshot: snapshot,
        merge: true,
      );
    }

    return;
  }

  /// Applies a snapshot received from the server
  bool applySnapshot(Snapshot snapshot) {
    return document.importSnapshot(snapshot);
  }

  /// Requests the missing changes from the server
  Future<void> _requestMissingChanges() async {
    await tryCatchIgnore(() {
      // Request a snapshot from the server
      return client.sendMessage(
        Message.snapshotRequest(
          documentId: _documentId,
          version: document.version,
        ),
      );
    });
  }

  /// Dispose the resources
  void dispose() {
    _localChangesSubscription?.cancel();
    _localChangesSubscription = null;

    _failuresHandler.dispose();
  }
}
