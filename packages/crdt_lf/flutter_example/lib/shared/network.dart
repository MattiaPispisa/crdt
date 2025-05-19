import 'dart:async';
import 'dart:collection'; // Import for Queue

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

/// Represents a simple broadcast network simulation with offline queuing.
///
/// Actors can send changes through the network and listen for changes
/// originating from other actors. Changes sent while offline are queued
/// and sent when the network comes back online.
class Network extends ChangeNotifier {
  // StreamController that broadcasts tuples of (senderId, change)
  final _changesController = StreamController<(PeerId, Change)>.broadcast();

  // Queue for changes made while offline
  final Queue<(PeerId, Change)> _offlineQueue = Queue();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  Duration _networkDelay = Duration.zero;
  Duration get networkDelay => _networkDelay;

  /// Sets the online status of the network.
  ///
  /// If transitioning to online, sends any queued offline changes.
  void setOnlineStatus(bool online) {
    // No change
    if (_isOnline == online) {
      return;
    }

    _isOnline = online;
    notifyListeners();

    if (_isOnline) {
      _flushOfflineQueue();
    }
  }

  /// Toggles the online status of the network.
  ///
  /// If transitioning to online, sends any queued offline changes.
  void toggleOnlineStatus() {
    _isOnline = !_isOnline;
    notifyListeners();

    if (_isOnline) {
      _flushOfflineQueue();
    }
  }

  void setNetworkDelay(Duration delay) {
    _networkDelay = delay;
    notifyListeners();
  }

  /// Sends a change into the network, attributed to the sender.
  ///
  /// If the network is online, the change is broadcast immediately.
  /// If offline, the change is queued and sent when the network comes back online.
  /// Listeners will receive this change unless their listener ID matches the senderId.
  Future<void> sendChange(Change change) async {
    final changeTuple = (change.author, change);
    if (_isOnline) {
      // Simulate network delay
      if (_networkDelay > Duration.zero) await Future.delayed(_networkDelay);

      _changesController.add(changeTuple);
    } else {
      _offlineQueue.add(changeTuple);
      notifyListeners();
    }
  }

  /// Sends all queued offline changes to the network.
  void _flushOfflineQueue() {
    while (_offlineQueue.isNotEmpty) {
      final changeTuple = _offlineQueue.removeFirst();
      _changesController.add(changeTuple);
    }
  }

  /// Listens for changes originating from other actors on the network.
  ///
  /// Returns a stream that emits [Change] objects sent by any actor
  /// whose ID does not match the provided [listenerId].
  Stream<Change> stream(PeerId listenerId) {
    return _changesController.stream
        // Filter out changes sent by the listener itself
        .where((event) => event.$1 != listenerId)
        // Extract only the Change object from the tuple
        .map((event) => event.$2);
  }

  int get offlineEvents => _offlineQueue.length;

  /// Disposes the network resources, closing the stream controller.
  @override
  void dispose() {
    _changesController.close();
    super.dispose();
  }
}
