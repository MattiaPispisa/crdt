import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';

// TODO(mattia): when server goes offline a version must be saved and on
// reconnecting every change from that version must be sent to the server.

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

  /// The socket client
  final CRDTSocketClient client;

  /// Subscription to the local changes stream
  StreamSubscription<Change>? _localChangesSubscription;

  /// Handles a local change
  Future<void> _handleLocalChange(Change change) async {
    // Send the change to the server
    await tryCatchIgnore(() async {
      await client.sendMessage(
        Message.change(
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
        Message.changes(
          documentId: document.documentId,
          changes: changes,
        ),
      );
    });
  }

  /// Applies a change
  void applyChange(Change change) {
    try {
      document.applyChange(change);
    } catch (e) {
      requestDocumentStatus();
    }
  }

  /// Applies a list of changes
  void applyChanges(List<Change> changes) {
    try {
      for (final change in changes) {
        document.applyChange(change);
      }
    } catch (e) {
      requestDocumentStatus();
    }
  }

  /// [CRDTDocument.import] with `merge: true`
  void merge({
    List<Change>? changes,
    Snapshot? snapshot,
  }) {
    final serverVV = _serverVersionVector(
      base: snapshot?.versionVector.mutable(),
      changes: changes,
    );

    document.import(
      changes: changes,
      snapshot: snapshot,
      merge: true,
    );

    _sendUnknownChangesToServer(serverVV);
  }

  /// Compute the server version from snapshot+changes
  VersionVector _serverVersionVector({
    VersionVector? base,
    List<Change>? changes,
  }) {
    final versionVector = base ?? VersionVector({});

    for (final c in changes ?? <Change>[]) {
      versionVector.update(c.id.peerId, c.hlc);
    }

    return versionVector;
  }

  /// Send local changes that are newer than the server's vector
  Future<void> _sendUnknownChangesToServer(VersionVector serverVV) async {
    final toSend = document.exportChangesNewerThan(serverVV);
    if (toSend.isEmpty) {
      return;
    }

    await _sendChangesToServer(toSend);
  }

  /// Requests the document status from the server
  Future<void> requestDocumentStatus() async {
    await tryCatchIgnore(() {
      // Request a snapshot from the server
      return client.sendMessage(
        Message.documentStatusRequest(
          documentId: document.documentId,
          version: document.version,
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
