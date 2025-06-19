import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';

// TODO(mattia): ChangeFailuresHandler can be removed in the future
// with new methods on [CRDTDocument] that permits to save the last sent change.
// This enables to export only changes during the offline period.

/// Handles [Change]s that failed to be sent to the server
class ChangeFailuresHandler {
  /// Constructor
  ChangeFailuresHandler({
    required this.client,
    required this.retryInterval,
  })  : _unSyncChanges = <Change>[],
        _isRetrying = false {
    // listen to the connection status
    _connectionStatusSubscription =
        client.connectionStatus.listen(_onConnectionStatus);
  }

  /// Handles the connection status
  void _onConnectionStatus(ConnectionStatus status) {
    if (status.isConnected) {
      _retryFailedChanges();
    }
  }

  /// The [Change]s that failed to be sent to the server
  final List<Change> _unSyncChanges;

  /// The [Change]s that failed to be sent to the server
  List<Change> get unSyncChanges => List.of(_unSyncChanges);

  /// Stream of the unSyncChanges
  Stream<int> get unSyncChangesCount => _unSyncChangesCountController.stream;

  /// Stream of the number of unSyncChanges
  final StreamController<int> _unSyncChangesCountController =
      StreamController<int>.broadcast();

  /// Whether the changes are being retried
  bool _isRetrying;

  /// The interval between retries
  final Duration retryInterval;

  /// The socket client
  final CRDTSocketClient client;

  /// Subscription to the connection status
  StreamSubscription<ConnectionStatus>? _connectionStatusSubscription;

  /// Adds a change to the list of changes to retry
  void add(Change change) {
    _unSyncChanges.add(change);
    _unSyncChangesCountController.add(_unSyncChanges.length);
  }

  /// Removes a change from the list of changes to retry
  void _pop() {
    _unSyncChanges.removeAt(0);
    _unSyncChangesCountController.add(_unSyncChanges.length);
  }

  /// Retry the changes
  ///
  /// The loop ends when:
  /// 1. there aren't changes to retry
  /// 2. the first change fails to be sent
  ///
  /// If a fails is encountered then the process restart after [retryInterval]
  Future<void> _retryFailedChanges() async {
    if (_isRetrying) {
      return;
    }

    _isRetrying = true;

    // no changes to retry
    if (_unSyncChanges.isEmpty) {
      _isRetrying = false;
      return;
    }

    await Future.doWhile(() async {
      if (_unSyncChanges.isEmpty) {
        return false;
      }

      try {
        final toSend = _unSyncChanges.first;
        await client.sendMessage(
          Message.change(
            documentId: client.document.peerId.toString(),
            change: toSend,
          ),
        );
        _pop();
      } catch (e) {
        return false;
      }

      return _unSyncChanges.isNotEmpty;
    });

    if (_unSyncChanges.isNotEmpty) {
      Timer(retryInterval, _retryFailedChanges);
    } else {
      _isRetrying = false;
    }
  }

  /// Dispose the resources
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _connectionStatusSubscription = null;
  }
}
