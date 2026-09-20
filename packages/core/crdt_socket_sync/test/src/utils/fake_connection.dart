import 'dart:async';

import 'package:crdt_socket_sync/server.dart';

/// A [TransportConnection] with no transport under it.
///
/// Tests push frames in with [receive] and read what the session wrote out of
/// [sent]. It is the shape an embedder hands to
/// [SessionHostServer.acceptConnection], so tests that use it exercise the
/// host without an HTTP server anywhere in sight.
class FakeTransportConnection implements TransportConnection {
  /// Constructor
  FakeTransportConnection();

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();

  /// Every frame the peer was sent, in order.
  final List<List<int>> sent = [];

  bool _isConnected = true;

  /// Whether [close] ran, on either end.
  bool get isClosed => !_isConnected;

  /// Deliver [data] to the session as an incoming frame.
  void receive(List<int> data) {
    if (_incoming.isClosed) {
      return;
    }
    _incoming.add(data);
  }

  /// End the stream the way a peer hanging up does.
  Future<void> endIncoming() async {
    if (_incoming.isClosed) {
      return;
    }
    await _incoming.close();
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> send(List<int> data) async {
    sent.add(data);
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  @override
  bool get isConnected => _isConnected;
}
