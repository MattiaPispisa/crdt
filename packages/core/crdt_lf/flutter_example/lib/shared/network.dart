import 'dart:async';
import 'dart:collection'; // Import for Queue
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Semantic latency levels for the simulated network.
///
/// Each level maps to an upper bound (in milliseconds); the actual delay
/// applied to a change is a random value in `[0, upperBoundMs]`.
enum DelayLevel {
  /// Snappy connection (up to 500ms).
  low(500, 'Low'),

  /// Average connection (up to 1.5s).
  medium(1500, 'Medium'),

  /// Sluggish connection (up to 4s).
  high(4000, 'High');

  const DelayLevel(this.upperBoundMs, this.label);

  /// Upper bound of the random delay, in milliseconds.
  final int upperBoundMs;

  /// Human-readable label.
  final String label;
}

/// Represents a simple broadcast network simulation with offline queuing.
///
/// Actors can send changes through the network and listen for changes
/// originating from other actors. Changes sent while offline are queued
/// and sent when the network comes back online.
///
/// When [randomDelay] is enabled, broadcasts are delayed by a random duration
/// bounded by [delayLevel], simulating the latency of a real connection.
/// Deliveries are still kept in order (like an ordered transport), so changes
/// never arrive before their causal dependencies.
class Network extends ChangeNotifier {
  // StreamController that broadcasts tuples of (senderId, change)
  final _changesController = StreamController<(PeerId, Change)>.broadcast();

  // Queue for changes made while offline
  final Queue<(PeerId, Change)> _offlineQueue = Queue();

  final Random _random = Random();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  bool _randomDelay = false;

  /// Whether broadcasts are delayed by a random latency (see [delayLevel]).
  bool get randomDelay => _randomDelay;

  DelayLevel _delayLevel = DelayLevel.medium;

  /// The semantic latency level used when [randomDelay] is enabled.
  DelayLevel get delayLevel => _delayLevel;

  /// Enables or disables the random broadcast delay.
  void setRandomDelay(bool enabled) {
    if (_randomDelay == enabled) {
      return;
    }
    _randomDelay = enabled;
    notifyListeners();
  }

  /// Sets the semantic latency [level] used when [randomDelay] is enabled.
  void setDelayLevel(DelayLevel level) {
    if (_delayLevel == level) {
      return;
    }
    _delayLevel = level;
    notifyListeners();
  }

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

  /// Sends a change into the network, attributed to the sender.
  ///
  /// If the network is online, the change is broadcast (immediately, or after a
  /// random delay when [randomDelay] is enabled).
  /// If offline, the change is queued and sent when the network comes back online.
  /// Listeners will receive this change unless their listener ID matches the senderId.
  void sendChange(Change change) {
    final changeTuple = (change.author, change);
    if (_isOnline) {
      _dispatch(changeTuple);
    } else {
      _offlineQueue.add(changeTuple);
      notifyListeners();
    }
  }

  /// Sends all queued offline changes to the network.
  void _flushOfflineQueue() {
    while (_offlineQueue.isNotEmpty) {
      _dispatch(_offlineQueue.removeFirst());
    }
  }

  // FIFO buffer of changes waiting to be delivered, each with its target
  // delivery time (ms). A single [_deliveryTimer] drains the front, so changes
  // are always emitted in send order — a jittered change can never overtake an
  // earlier one and reach a peer before its causal dependencies.
  final Queue<(int, (PeerId, Change))> _delayedQueue = Queue();
  Timer? _deliveryTimer;

  /// Broadcasts [changeTuple], applying the random delay when enabled.
  void _dispatch((PeerId, Change) changeTuple) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final jitter =
        _randomDelay ? _random.nextInt(_delayLevel.upperBoundMs + 1) : 0;

    // No latency and nothing already waiting: deliver right away.
    if (jitter == 0 && _delayedQueue.isEmpty) {
      _emit(changeTuple);
      return;
    }

    _delayedQueue.add((nowMs + jitter, changeTuple));
    _scheduleDelivery();
  }

  /// Arms a single timer for the front of [_delayedQueue], if not already set.
  void _scheduleDelivery() {
    if (_deliveryTimer != null || _delayedQueue.isEmpty) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waitMs = max(0, _delayedQueue.first.$1 - nowMs);
    _deliveryTimer = Timer(Duration(milliseconds: waitMs), () {
      _deliveryTimer = null;
      final deadline = DateTime.now().millisecondsSinceEpoch;
      // Drain every change that is due, in FIFO (send) order.
      while (_delayedQueue.isNotEmpty && _delayedQueue.first.$1 <= deadline) {
        _emit(_delayedQueue.removeFirst().$2);
      }
      _scheduleDelivery();
    });
  }

  /// Adds [changeTuple] to the broadcast stream unless it has been closed.
  void _emit((PeerId, Change) changeTuple) {
    if (_changesController.isClosed) {
      return;
    }
    _changesController.add(changeTuple);
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
    _deliveryTimer?.cancel();
    _changesController.close();
    super.dispose();
  }
}

class NetworkProvider extends StatelessWidget {
  /// Provide to children a [Network] instance.
  const NetworkProvider({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(create: (context) => Network(), child: child);
  }
}
