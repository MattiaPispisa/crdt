import 'dart:async';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client/client.dart';
import 'package:crdt_socket_sync/src/client/status.dart';
import 'package:crdt_socket_sync/src/client/sync_manager.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/common/utils.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// [CRDTSocketClient] implementation using web socket
class WebSocketClient extends CRDTSocketClient {
  /// Constructor
  WebSocketClient({
    required this.url,
    required this.document,
    required this.author,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    super.plugins,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast()
              ..add(ConnectionStatus.disconnected),
        _connectionStatusValue = ConnectionStatus.disconnected,
        _transportConnectorFactory = (() => _WebSocketConnector(url)) {
    _syncManager = SyncManager(document: document, client: this);
    _messageCodec = CompressedCodec<Message>(
      PluginAwareMessageCodec.fromPlugins(
        plugins: plugins,
        defaultCodec: messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: Message.fromJson,
            ),
      ),
      compressor: compressor ?? NoCompression.instance,
    );

    messages.listen(_handleMessage);
  }

  /// Constructor for testing
  WebSocketClient.test({
    required this.url,
    required this.document,
    required this.author,
    required TransportConnector Function() transportConnectorFactory,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    super.plugins,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast()
              ..add(ConnectionStatus.disconnected),
        _connectionStatusValue = ConnectionStatus.disconnected,
        _transportConnectorFactory = transportConnectorFactory {
    _syncManager = SyncManager(document: document, client: this);
    _messageCodec = CompressedCodec<Message>(
      PluginAwareMessageCodec.fromPlugins(
        plugins: plugins,
        defaultCodec: messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: Message.fromJson,
            ),
      ),
      compressor: compressor ?? NoCompression.instance,
    );

    messages.listen(_handleMessage);
  }

  @override
  final CRDTDocument document;

  /// Author of the document
  @override
  final PeerId author;

  /// WebSocket server URL
  final String url;

  /// Session ID
  String? _sessionId;

  @override
  String? get sessionId => _sessionId;

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

  final TransportConnector Function() _transportConnectorFactory;

  /// Number of reconnect attempts
  int _reconnectAttempts = 0;

  /// If client is reconnecting
  bool _isReconnecting = false;

  /// Timer for periodic ping
  Timer? _pingTimer;

  /// Completer for handshake
  Completer<bool>? _handshakeCompleter;

  /// Whether the handshake is resolved and completed
  ///
  /// If [_handshakeCompleter] is not completed
  /// then the future is resolved to false.
  ///
  /// No waiting is done here.
  Future<bool> get _handshakeCompleted {
    if (_handshakeCompleter == null) {
      return Future.value(false);
    }

    if (!_handshakeCompleter!.isCompleted) {
      return Future.value(false);
    }

    return _handshakeCompleter!.future;
  }

  /// Whether the client is handshaking
  bool get _handshaking =>
      _handshakeCompleter != null && !_handshakeCompleter!.isCompleted;

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
    if (_connectionStatusValue.isConnected) {
      return true;
    }

    if (_handshaking) {
      // already under connection
      return _handshakeCompleter!.future;
    }

    try {
      final connector = _transportConnectorFactory();

      await tryCatchIgnore(() async {
        await _transport?.close();
      });

      _transport = Transport.create(connector);

      _updateConnectionStatus(
        _connectionStatusValue.isDisconnected
            ? ConnectionStatus.connecting
            : ConnectionStatus.reconnecting,
      );

      _transport!.incoming.listen(
        _handleIncomingData,
        onError: (dynamic error, _) {
          _handleTransportError(error);
        },
      );

      final connected = await _performHandshake();
      if (connected) {
        _startPingTimer();
        _updateConnectionStatus(ConnectionStatus.connected);
        for (final plugin in plugins) {
          plugin.onConnected();
        }
      }

      return connected;
    } catch (e) {
      _updateConnectionStatus(ConnectionStatus.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _stopPingTimer();

    if (_transport == null) {
      return;
    }

    await tryCatchIgnore(() async {
      await _transport!.close();
    });
    _transport = null;

    for (final plugin in plugins) {
      plugin.onDisconnected();
    }

    _updateConnectionStatus(ConnectionStatus.disconnected);
  }

  /// Send a message to the server
  ///
  /// If [attemptReconnect] is true, then the client will attempt to reconnect
  /// on connection error
  @override
  Future<void> sendMessage(
    Message message, {
    bool attemptReconnect = true,
  }) async {
    if (_connectionStatusValue.isDisconnected || _transport == null) {
      throw StateError('Client not connected');
    }

    final data = _messageCodec.encode(message);

    // ignore: prefer_asserts_with_message assert function
    assert(() {
      if (data == null) {
        throw StateError(
          '[WebSocketClient] cannot send a message that cannot be encoded.'
          ' Have you added the plugin to the client?'
          '\nMessage: $message',
        );
      }
      return true;
    }());

    if (data == null) {
      return;
    }

    try {
      await _transport!.send(data);

      if (await _handshakeCompleted) {
        _updateConnectionStatus(ConnectionStatus.connected);
      }
    } catch (e) {
      _handleTransportError(
        e,
        attemptReconnect: attemptReconnect,
      );
      rethrow;
    }
  }

  @override
  Future<void> sendChange(Change change) async {
    await tryCatchIgnore(() async {
      final message = Message.change(
        documentId: document.documentId,
        change: change,
      );
      await sendMessage(message);
    });
  }

  @override
  Future<void> requestSync() async {
    await tryCatchIgnore(() async {
      await _syncManager.requestDocumentStatus();
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

        // ignore: prefer_asserts_with_message assert function
        assert(() {
          if (message == null) {
            throw StateError(
              '[WebSocketClient] received a message that cannot be decoded.'
              ' Have you added the plugin to the client?'
              '\nBuffer: ${_buffer.join(', ')}',
            );
          }
          if (_messageController.isClosed) {
            throw StateError(
              '[WebSocketClient] received a message after the client has been'
              ' disposed',
            );
          }
          return true;
        }());

        _buffer.clear();

        if (message != null && !_messageController.isClosed) {
          _messageController.add(message);
        }
      } catch (e) {
        // not enough data for a message
        break;
      }
    }
  }

  /// set status with [ConnectionStatus.error]
  /// and attempt to reconnect ([_attemptReconnect])
  void _handleTransportError(
    dynamic error, {
    bool attemptReconnect = true,
  }) {
    if (_handshaking || _handshakeCompleter != null) {
      _resetHandshake();
    }

    // on reconnecting if an error occurs do not update the status
    // to error, because the reconnect will handle it.
    if (!_isReconnecting) {
      _updateConnectionStatus(ConnectionStatus.error);
    }
    if (attemptReconnect) {
      _attemptReconnect();
    }
  }

  /// Attempt to reconnect calling with [Protocol.reconnectInterval] interval
  /// the [connect] method
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) {
      return;
    }

    _isReconnecting = true;

    if (_reconnectAttempts >= Protocol.maxReconnectAttempts) {
      _updateConnectionStatus(ConnectionStatus.error);
      _isReconnecting = false;
      return;
    }

    _reconnectAttempts++;
    _updateConnectionStatus(ConnectionStatus.reconnecting);

    await Future<void>.delayed(Protocol.reconnectInterval);

    try {
      final success = await connect();
      if (success) {
        _reconnectAttempts = 0;
      }
    } finally {
      _isReconnecting = false;
    }

    if (!_connectionStatusValue.isConnected) {
      unawaited(_attemptReconnect());
    }
  }

  /// Start the periodic ping [_sendPing] with [Protocol.pingInterval] interval
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      Protocol.pingInterval,
      (_) => _sendPing(),
    );
  }

  /// Stop the periodic ping
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send a ping message to the server
  Future<void> _sendPing() async {
    if (!_connectionStatusValue.isDisconnected) {
      await tryCatchIgnore(() async {
        final pingMessage = Message.ping(
          documentId: document.documentId,
          timestamp: DateTime.now().millisecondsSinceEpoch,
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
  ///
  /// Handshake is not attempted to reconnect
  Future<bool> _performHandshake() async {
    _handshakeCompleter = Completer<bool>();

    final handshakeRequest = HandshakeRequestMessage(
      versionVector: document.getVersionVector(),
      documentId: document.documentId,
      author: author,
    );

    try {
      // do not attempt to reconnect on handshake error
      // because the reconnect will handle it.
      await sendMessage(
        handshakeRequest,
        attemptReconnect: false,
      );

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
    if (message.documentId != document.documentId) {
      return;
    }

    for (final plugin in plugins) {
      plugin.onMessage(message);
    }

    switch (message.type) {
      case MessageType.handshakeResponse:
        _handleHandshakeResponse(message as HandshakeResponseMessage);
        break;

      case MessageType.change:
        _handleChangeMessage(message as ChangeMessage);
        break;

      case MessageType.documentStatus:
        _handleDocumentStatusMessage(message as DocumentStatusMessage);
        break;

      case MessageType.ping:
        await _handlePingMessage(message as PingMessage);
        break;

      case MessageType.error:
        _handleErrorMessage(message as ErrorMessage);
        break;

      case MessageType.pong:
      case MessageType.handshakeRequest:
      case MessageType.documentStatusRequest:
        break;
    }
  }

  /// Handles the handshake response
  ///
  /// Merges the changes and snapshot into the document
  /// and completes the handshake
  void _handleHandshakeResponse(HandshakeResponseMessage message) {
    _sessionId = message.sessionId;

    _syncManager.merge(
      changes: message.changes,
      snapshot: message.snapshot,
      serverVersionVector: message.versionVector,
    );
    _handshakeCompleter?.complete(true);
  }

  void _handleChangeMessage(ChangeMessage message) {
    _syncManager.applyChange(message.change);
  }

  void _handleDocumentStatusMessage(DocumentStatusMessage message) {
    _syncManager.merge(
      changes: message.changes,
      snapshot: message.snapshot,
      serverVersionVector: message.versionVector,
    );
  }

  Future<void> _handlePingMessage(PingMessage message) async {
    final pongMessage = PongMessage(
      documentId: document.documentId,
      originalTimestamp: message.timestamp,
      responseTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await sendMessage(pongMessage);
  }

  void _handleErrorMessage(ErrorMessage message) {
    if (message.code == Protocol.errorOutOfSync) {
      requestSync();
      return;
    }

    _updateConnectionStatus(ConnectionStatus.error);

    if (message.code == Protocol.errorHandshakeFailed &&
        _handshakeCompleter != null) {
      _resetHandshake();
    }
  }

  /// If [status] is different from [_connectionStatusValue]
  /// then update the connection status and notify the listeners
  void _updateConnectionStatus(ConnectionStatus status) {
    if (status == _connectionStatusValue) {
      return;
    }

    _connectionStatusValue = status;
    if (_connectionStatusController.isClosed) {
      return;
    }

    _connectionStatusController.add(status);
  }

  /// Reset the handshake completer
  void _resetHandshake() {
    if (_handshakeCompleter?.isCompleted == false) {
      _handshakeCompleter?.complete(false);
    }
    _handshakeCompleter = null;
  }

  @override
  void dispose() {
    disconnect();

    for (final plugin in plugins) {
      plugin.dispose();
    }

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
