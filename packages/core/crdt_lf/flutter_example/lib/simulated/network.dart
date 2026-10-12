import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:flutter/foundation.dart';

/// Semantic latency levels for the simulated network.
///
/// Each level maps to an upper bound (in milliseconds); the actual delay
/// applied to a delivery is a random value in `[0, upperBoundMs]`.
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

/// An in-memory network between the [SimulatedSocketClient]s of one app.
///
/// A change reaches the connected clients of the same document. Going
/// online connects every client, and a client that connects catches up with
/// the others, so edits made offline converge.
///
/// With [randomDelay], each delivery waits a random time bounded by
/// [delayLevel]. Deliveries keep the send order, like an ordered transport.
class SimulatedNetwork extends ChangeNotifier {
  /// Creates an offline network; [random] picks the delays.
  SimulatedNetwork({Random? random})
    : _random = random ?? Random(),
      _clients = {},
      _connected = {},
      _deliveries = Queue();

  final Random _random;

  final Set<SimulatedSocketClient> _clients;

  final Set<SimulatedSocketClient> _connected;

  // A single timer drains the front of this queue, so deliveries keep the
  // send order: a delayed change never overtakes an earlier one.
  final Queue<_Delivery> _deliveries;

  Timer? _deliveryTimer;

  bool _isOnline = false;

  /// Whether the clients are connected.
  bool get isOnline => _isOnline;

  bool _randomDelay = false;

  /// Whether deliveries wait a random time (see [delayLevel]).
  bool get randomDelay => _randomDelay;

  DelayLevel _delayLevel = DelayLevel.medium;

  /// The latency level used when [randomDelay] is on.
  DelayLevel get delayLevel => _delayLevel;

  /// Connects every client when [online], disconnects them otherwise.
  // A `Switch.onChanged` tear-off: the flag stays positional.
  // ignore: avoid_positional_boolean_parameters
  void setOnlineStatus(bool online) {
    if (_isOnline == online) {
      return;
    }
    _isOnline = online;
    notifyListeners();
    for (final client in _clients.toList()) {
      unawaited(online ? client.connect() : client.disconnect());
    }
  }

  /// Turns the random delay on or off.
  // A `Switch.onChanged` tear-off: the flag stays positional.
  // ignore: avoid_positional_boolean_parameters
  void setRandomDelay(bool enabled) {
    if (_randomDelay == enabled) {
      return;
    }
    _randomDelay = enabled;
    notifyListeners();
  }

  /// Sets the latency [level] used when [randomDelay] is on.
  void setDelayLevel(DelayLevel level) {
    if (_delayLevel == level) {
      return;
    }
    _delayLevel = level;
    notifyListeners();
  }

  bool _connect(SimulatedSocketClient client) {
    if (!_isOnline) {
      client._setStatus(ConnectionStatus.disconnected);
      return false;
    }
    if (_connected.add(client)) {
      client._setStatus(ConnectionStatus.connected);
      for (final peer in _peersOf(client)) {
        _send(peer, client, () => client._catchUpFrom(peer));
        _send(client, peer, () => peer._catchUpFrom(client));
      }
    }
    return true;
  }

  void _disconnect(SimulatedSocketClient client) {
    if (_connected.remove(client)) {
      client._setStatus(ConnectionStatus.disconnected);
    }
  }

  void _detach(SimulatedSocketClient client) {
    _disconnect(client);
    _clients.remove(client);
  }

  void _broadcast(SimulatedSocketClient from, Change change) {
    if (!_connected.contains(from)) {
      return;
    }
    for (final peer in _peersOf(from)) {
      _send(from, peer, () => peer._receive(change));
    }
  }

  void _requestCatchUp(SimulatedSocketClient client) {
    for (final peer in _peersOf(client)) {
      _send(peer, client, () => client._catchUpFrom(peer));
    }
  }

  Iterable<SimulatedSocketClient> _peersOf(SimulatedSocketClient client) {
    final documentId = client.document.documentId;
    return _connected.where(
      (peer) =>
          !identical(peer, client) && peer.document.documentId == documentId,
    );
  }

  void _send(
    SimulatedSocketClient from,
    SimulatedSocketClient to,
    void Function() deliver,
  ) {
    final jitter =
        _randomDelay ? _random.nextInt(_delayLevel.upperBoundMs + 1) : 0;
    final delivery = _Delivery(
      dueMs: DateTime.now().millisecondsSinceEpoch + jitter,
      from: from,
      to: to,
      deliver: deliver,
    );

    if (jitter == 0 && _deliveries.isEmpty) {
      _run(delivery);
      return;
    }
    _deliveries.add(delivery);
    _scheduleDelivery();
  }

  void _scheduleDelivery() {
    if (_deliveryTimer != null || _deliveries.isEmpty) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waitMs = max(0, _deliveries.first.dueMs - nowMs);
    _deliveryTimer = Timer(Duration(milliseconds: waitMs), () {
      _deliveryTimer = null;
      final deadline = DateTime.now().millisecondsSinceEpoch;
      while (_deliveries.isNotEmpty && _deliveries.first.dueMs <= deadline) {
        _run(_deliveries.removeFirst());
      }
      _scheduleDelivery();
    });
  }

  void _run(_Delivery delivery) {
    // Lost on the way when either side went offline: the next connect
    // catches up.
    if (_connected.contains(delivery.from) &&
        _connected.contains(delivery.to)) {
      delivery.deliver();
    }
  }

  @override
  void dispose() {
    _deliveryTimer?.cancel();
    _deliveries.clear();
    super.dispose();
  }
}

/// A [CRDTSocketClient] over a [SimulatedNetwork], with no server.
///
/// It connects only while the network is online. On connect it exchanges
/// with the other connected peers what each one misses. A pruned history
/// travels as the latest snapshot. It runs no plugin.
class SimulatedSocketClient extends CRDTSocketClient {
  /// Creates a client that syncs [document] over [network].
  SimulatedSocketClient({
    required this.document,
    required SimulatedNetwork network,
  }) : _network = network {
    _localChanges = document.localChanges.listen(sendChange);
    network._clients.add(this);
  }

  @override
  final CRDTDocument document;

  final SimulatedNetwork _network;

  late final StreamSubscription<Change> _localChanges;

  @override
  PeerId get author => document.peerId;

  @override
  String? get sessionId =>
      connectionStatusValue.isConnected ? author.toString() : null;

  @override
  Stream<Message> get messages => const Stream.empty();

  @override
  Future<bool> connect() async => _network._connect(this);

  @override
  Future<void> disconnect() async => _network._disconnect(this);

  @override
  Future<void> sendMessage(Message message) async {}

  @override
  Future<void> sendChange(Change change) async =>
      _network._broadcast(this, change);

  @override
  Future<void> requestSync() async => _network._requestCatchUp(this);

  @override
  void dispose() {
    unawaited(_localChanges.cancel());
    _network._detach(this);
    closeClientStreams();
  }

  void _setStatus(ConnectionStatus status) => updateConnectionStatus(status);

  void _receive(Change change) {
    try {
      document.applyChange(change);
    } on CausallyNotReadyException {
      unawaited(requestSync());
    } on MissingDependencyException {
      unawaited(requestSync());
    } catch (error, stackTrace) {
      _fault('Could not apply change ${change.id}', error, stackTrace);
    }
  }

  void _catchUpFrom(SimulatedSocketClient peer) {
    final version = document.getVersionVector();
    final changes = peer.document.exportChangesNewerThan(version);
    final snapshot = peer.document.snapshot;
    try {
      // The peer pruned history this document never saw: what is left of it
      // is in the snapshot.
      if (snapshot != null &&
          !version.isStrictlyNewerOrEqualThan(snapshot.versionVector) &&
          document.import(snapshot: snapshot, changes: changes) >= 0) {
        return;
      }
      document.importChanges(changes);
    } catch (error, stackTrace) {
      _fault('Could not catch up with ${peer.author}', error, stackTrace);
    }
  }

  void _fault(String reason, Object error, StackTrace stackTrace) {
    reportSyncFault(
      SyncFault(reason: reason, error: error, stackTrace: stackTrace),
    );
  }
}

class _Delivery {
  _Delivery({
    required this.dueMs,
    required this.from,
    required this.to,
    required this.deliver,
  });

  final int dueMs;
  final SimulatedSocketClient from;
  final SimulatedSocketClient to;
  final void Function() deliver;
}
