import 'dart:async';

import 'package:crdt_socket_sync/src/common/common/transporter.dart';

/// A [TransportConnection] with no transport under it.
///
/// Tests push frames in with [receive] and read what the peer was sent out of
/// [sent]. It is the shape a server host is handed by an embedder and the
/// shape a `Transport` gets from its connector, so both ends of the package
/// can be driven with it and no HTTP server anywhere in sight.
class FakeTransportConnection implements TransportConnection {
  /// Constructor
  FakeTransportConnection();

  // Broadcast so a test may listen alongside the code under test. Sessions
  // and transports subscribe as they are built, before the first `receive`,
  // so nothing is dropped for want of a listener.
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();

  /// Every frame the peer was sent, in order.
  final List<List<int>> sent = [];

  bool _isConnected = true;

  /// Whether this connection was closed, on either end.
  bool get isClosed => !_isConnected;

  /// Deliver [data] as an incoming frame.
  void receive(List<int> data) {
    if (_incoming.isClosed) {
      return;
    }
    _incoming.add(data);
  }

  /// Fail the incoming stream, the way a broken socket does.
  void receiveError(Object error) {
    if (_incoming.isClosed) {
      return;
    }
    _incoming.addError(error);
  }

  /// End the stream the way a peer hanging up does.
  ///
  /// Unlike [close] this is the *other* end letting go, which is why it also
  /// clears [isConnected]: code that checks before reusing a connection has
  /// to see a dead one.
  Future<void> peerCloses() async {
    _isConnected = false;
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
