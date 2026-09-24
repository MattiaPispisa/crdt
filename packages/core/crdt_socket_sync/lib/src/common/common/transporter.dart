import 'dart:async';

/// An interface for transporting messages,
/// define the methods necessary to send and receive messages,
/// independently from the underlying transport mechanism.
abstract class Transport {
  /// Create a new transport
  factory Transport.create(TransportConnector connector) {
    return _TransportImpl(connector);
  }

  /// Stream of incoming messages
  Stream<List<int>> get incoming;

  /// Send a message
  Future<void> send(List<int> data);

  /// Close the connection
  Future<void> close();

  /// Whether the connection is active
  bool get isConnected;
}

/// An interface for the transport connection
abstract class TransportConnector {
  /// Create a connection
  Future<TransportConnection> connect();
}

/// An interface for transporting messages,
/// define the methods necessary to send and receive messages,
/// independently from the underlying transport mechanism.
///
/// ## Messages, not bytes
///
/// The transport has to keep the message boundaries: one [send] must reach
/// the peer as exactly one event on its [incoming]. Every frame is decoded on
/// its own, so a frame that arrives split in two, or glued to the next one,
/// does not decode and is reported as undecodable instead of being buffered.
///
/// A WebSocket, an isolate port or an in-memory pipe give this for free. A
/// raw TCP socket does not — it delivers whatever chunks it pleases, so it
/// needs a framing layer of its own underneath.
abstract class TransportConnection {
  /// Stream of incoming data, one event per message sent by the peer.
  Stream<List<int>> get incoming;

  /// Send [data] as a single message.
  Future<void> send(List<int> data);

  /// Close the connection
  Future<void> close();

  /// Whether the connection is active
  bool get isConnected;
}

/// Internal implementation of the transport
class _TransportImpl implements Transport {
  _TransportImpl(this._connector);

  final TransportConnector _connector;
  TransportConnection? _connection;
  StreamSubscription<List<int>>? _incomingSubscription;

  final _incomingController = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incoming => _incomingController.stream;

  @override
  Future<void> send(List<int> data) async {
    if (_incomingController.isClosed) {
      throw StateError(
        'This transport is done: the peer closed the connection, or close() '
        'ran. Open a new one instead of sending on it.',
      );
    }

    if (_connection == null || !_connection!.isConnected) {
      await _connect();
    }

    await _connection!.send(data);
  }

  @override
  Future<void> close() async {
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _connection?.close();
    _connection = null;
    await _incomingController.close();
  }

  @override
  bool get isConnected => _connection?.isConnected ?? false;

  Future<void> _connect() async {
    await _incomingSubscription?.cancel();
    _connection = await _connector.connect();

    // Forward incoming messages to the controller
    _incomingSubscription = _connection!.incoming.listen(
      _incomingController.add,
      onError: _incomingController.addError,
      onDone: _handlePeerClosed,
    );
  }

  /// Ends this transport, reporting the close on [incoming] as an error.
  void _handlePeerClosed() {
    _connection = null;
    if (_incomingController.isClosed) {
      return;
    }

    // An error, because a consumer of [incoming] gets no onDone of its own:
    // without it the peer's close is silent.
    _incomingController.addError(
      StateError('The peer closed the connection.'),
    );
    unawaited(_incomingController.close());
  }
}
