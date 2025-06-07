import 'dart:async';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client/client.dart';
import 'package:crdt_socket_sync/src/client/status.dart';
import 'package:crdt_socket_sync/src/client/sync_manager.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// [CRDTSocketClient] implementation using web socket
class WebSocketClient implements CRDTSocketClient {
  /// Constructor
  WebSocketClient({
    required this.url,
    required this.document,
    required this.author,
    Compressor? compressor,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast(),
        _connectionStatusValue = ConnectionStatus.disconnected {
    _syncManager = SyncManager(document: document, client: this);

    _messageCodec = CompressedCodec<Message>(
      JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: Message.fromJson,
      ),
      compressor: compressor ?? NoCompression.instance,
    );

    messages.listen(_handleMessage);
  }

  @override
  final CRDTDocument document;
  String get _documentId => document.peerId.toString();

  /// Author of the document
  @override
  final PeerId author;

  /// WebSocket server URL
  final String url;

  /// Sync manager
  late final SyncManager _syncManager;

  /// Transport for communication
  Transport? _transport;

  /// Buffer for incoming data
  final List<int> _buffer = [];

  /// Incoming (transporter) messages controller
  final StreamController<Message> _messageController;

  /// Connection status controller
  final StreamController<ConnectionStatus> _connectionStatusController;
  ConnectionStatus _connectionStatusValue;

  /// If client is connected
  bool _isConnected = false;

  /// If client is reconnecting
  bool _isReconnecting = false;

  /// Number of reconnect attempts
  int _reconnectAttempts = 0;

  /// Timer for periodic ping
  Timer? _pingTimer;

  /// Completer for handshake
  Completer<bool>? _handshakeCompleter;

  /// Codec for messages
  late final MessageCodec<Message> _messageCodec;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  ConnectionStatus get connectionStatusValue => _connectionStatusValue;

  @override
  Stream<Message> get messages => _messageController.stream;

  /// Connect to the server
  ///
  /// Returns true if the connection is successful, false otherwise
  ///
  /// 1. Setup the [Transport] for the connection
  /// 1. Start listening for incoming data
  /// 1. Start the ping timer
  /// 1. Perform the handshake
  ///
  /// If the handshake is successful then incoming messages are handled
  /// by [messages] stream
  ///
  /// If the handshake fails then the client will attempt to reconnect
  @override
  Future<bool> connect() async {
    if (_isConnected) {
      return true;
    }

    try {
      final connector = _WebSocketConnector(url);

      _transport = Transport.create(connector);

      _isConnected = true;
      _reconnectAttempts = 0;
      _updateConnectionStatus(ConnectionStatus.connected);

      _transport!.incoming.listen(
        _handleIncomingData,
        onError: _handleTransportError,
        onDone: disconnect,
      );

      _startPingTimer();

      final connected = await _performHandshake();

      if (!connected) {
        _updateConnectionStatus(ConnectionStatus.error);
      }
      return connected;
    } catch (e) {
      _updateConnectionStatus(ConnectionStatus.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _stopPingTimer();

    if (_transport != null) {
      await _transport!.close();
      _transport = null;
    }

    _updateConnectionStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendMessage(Message message) async {
    if (!_isConnected || _transport == null) {
      throw StateError('Client not connected');
    }

    final data = _messageCodec.encode(message);
    await _transport!.send(data);
  }

  @override
  Future<void> sendChange(Change change) async {
    await tryCatchIgnore(() async {
      final message = Message.change(_documentId, change);
      await sendMessage(message);
    });
  }

  @override
  Future<void> requestSnapshot() async {
    await tryCatchIgnore(() async {
      final message = Message.snapshotRequest(
        _documentId,
        document.version,
      );
      await sendMessage(message);
    });
  }

  void _handleIncomingData(List<int> data) {
    _buffer.addAll(data);
    _processBuffer();
  }

  void _processBuffer() {
    while (_buffer.isNotEmpty) {
      try {
        final message = _messageCodec.decode(_buffer);

        _buffer.clear();

        _messageController.add(message);
      } catch (e) {
        // not enough data for a message
        break;
      }
    }
  }

  void _handleTransportError(error) {
    _updateConnectionStatus(ConnectionStatus.error);
    _attemptReconnect();
  }

  Future<void> _attemptReconnect() async {
    if (_isReconnecting ||
        _reconnectAttempts >= Protocol.maxReconnectAttempts) {
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    _updateConnectionStatus(ConnectionStatus.reconnecting);

    await Future<void>.delayed(Protocol.reconnectInterval);

    try {
      final success = await connect();
      if (success) {
        _reconnectAttempts = 0;
      }
    } catch (e) {
      // Ignore error, will be handled by the next attempt
    } finally {
      _isReconnecting = false;
    }
  }

  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      Protocol.pingInterval,
      (_) => _sendPing(),
    );
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _sendPing() async {
    if (_isConnected) {
      await tryCatchIgnore(() async {
        final pingMessage = Message.ping(
          _documentId,
          DateTime.now().millisecondsSinceEpoch,
        );
        await sendMessage(pingMessage);
      });
    }
  }

  /// Performs the handshake with the server
  ///
  /// Returns true if the handshake is successful, false otherwise
  ///
  /// [Protocol.handshakeTimeout] is the maximum time to wait
  /// for the handshake response
  Future<bool> _performHandshake() async {
    _handshakeCompleter = Completer<bool>();

    final handshakeRequest = HandshakeRequestMessage(
      version: document.version,
      documentId: _documentId,
      author: author,
    );

    try {
      await sendMessage(handshakeRequest);

      final timeout = Future.delayed(
        Protocol.handshakeTimeout,
        () => false,
      );

      // start a race with a timeout.
      // _handshakeCompleter will complete in _handleMessage
      return await Future.any([_handshakeCompleter!.future, timeout]);
    } catch (e) {
      _handshakeCompleter?.complete(false);
      return false;
    }
  }

  /// Handles incoming messages
  Future<void> _handleMessage(Message message) async {
    if (message.documentId != _documentId) {
      return;
    }

    switch (message.type) {
      case MessageType.handshakeResponse:
        _handleHandshakeResponse(message as HandshakeResponseMessage);
        break;

      case MessageType.change:
        _handleChangeMessage(message as ChangeMessage);
        break;

      case MessageType.snapshot:
        _handleSnapshotMessage(message as SnapshotMessage);
        break;

      case MessageType.ping:
        await _handlePingMessage(message as PingMessage);
        break;

      case MessageType.error:
        _handleErrorMessage(message as ErrorMessage);
        break;

      case MessageType.pong:
      case MessageType.handshakeRequest:
      case MessageType.snapshotRequest:
        break;
    }
  }

  void _handleHandshakeResponse(HandshakeResponseMessage message) {
    if (message.snapshot != null) {
      _syncManager.applySnapshot(message.snapshot!);
    }

    if (message.changes != null && message.changes!.isNotEmpty) {
      _syncManager.applyChanges(message.changes!);
    }

    _handshakeCompleter?.complete(true);
    _handshakeCompleter = null;
  }

  void _handleChangeMessage(ChangeMessage message) {
    _syncManager.applyChange(message.change);
  }

  void _handleSnapshotMessage(SnapshotMessage message) {
    _syncManager.applySnapshot(message.snapshot);
  }

  Future<void> _handlePingMessage(PingMessage message) async {
    final pongMessage = PongMessage(
      documentId: _documentId,
      originalTimestamp: message.timestamp,
      responseTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await sendMessage(pongMessage);
  }

  void _handleErrorMessage(ErrorMessage message) {
    _updateConnectionStatus(ConnectionStatus.error);

    if (message.code == Protocol.errorHandshakeFailed &&
        _handshakeCompleter != null) {
      _handshakeCompleter?.complete(false);
      _handshakeCompleter = null;
    }
  }

  void _updateConnectionStatus(ConnectionStatus status) {
    _connectionStatusValue = status;
    if (_connectionStatusController.isClosed) {
      return;
    }
    _connectionStatusController.add(status);
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStatusController.close();
    _syncManager.dispose();
  }
}

/// Connect using [WebSocketChannel.connect]
class _WebSocketConnector implements TransportConnector {
  _WebSocketConnector(this.url);

  /// The WebSocket server URL
  final String url;

  @override
  Future<TransportConnection> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));

    await channel.ready;

    return _WebSocketConnection(channel);
  }
}

/// WebSocket connection
class _WebSocketConnection implements TransportConnection {
  /// Constructor
  _WebSocketConnection(this._channel);

  /// The WebSocket channel
  final WebSocketChannel _channel;

  @override
  Stream<List<int>> get incoming {
    return _channel.stream.map((data) {
      if (data is String) {
        return List<int>.from(data.codeUnits);
      } else if (data is List<int>) {
        return data;
      }

      throw FormatException('Unexpected data type: ${data.runtimeType}');
    });
  }

  @override
  Future<void> send(List<int> data) async {
    _channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close(normalClosure);
  }

  @override
  bool get isConnected => _channel.closeCode == null;
}
