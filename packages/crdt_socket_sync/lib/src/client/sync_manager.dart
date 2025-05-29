import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client/client.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';

/// Manager for the CRDT client
class SyncManager {
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

  /// The document ID
  String get _documentId => document.peerId.toString();

  /// The socket client
  final CRDTSocketClient client;

  /// Subscription to the local changes stream
  StreamSubscription<Change>? _localChangesSubscription;

  /// Handles a local change
  Future<void> _handleLocalChange(Change change) async {
    // Send the change to the server
    return tryCatchIgnore(
      () => client.sendMessage(Message.change(_documentId, change)),
    );
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
    for (final change in changes) {
      applyChange(change);
    }
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
          _documentId,
          document.version,
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
