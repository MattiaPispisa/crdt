import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/client.dart';
import 'package:crdt_socket_sync/src/common/client/handshake_gate.dart';
import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/client/web_socket/channel_connector.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';
import 'package:crdt_socket_sync/src/server_client/client/sync_manager.dart';
import 'package:crdt_socket_sync/src/server_client/common/common.dart';

/// [CRDTSocketClient] implementation using web socket
class WebSocketClient extends CRDTSocketClient {
  /// Constructor
  WebSocketClient({
    required this.url,
    required this.document,
    required this.author,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    Duration? pingInterval,
    Duration? pingTimeout,
    int? maxBufferSize,
    super.plugins,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast()
              ..add(ConnectionStatus.disconnected),
        _connectionStatusValue = ConnectionStatus.disconnected,
        _pingInterval = pingInterval ?? Protocol.pingInterval,
        _pingTimeout = pingTimeout ?? Protocol.pingTimeout,
        _maxBufferSize = maxBufferSize ?? Protocol.maxBufferSize,
        _handshakeGate = HandshakeGate(),
        _transportFactory =
            (() => Transport.create(WebSocketChannelConnector(url))) {
    _syncManager = SyncManager(document: document, client: this);
    _messageCodec = CompressedCodec<Message>(
      PluginAwareMessageCodec.fromPlugins(
        plugins: plugins,
        defaultCodec: messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: (json) =>
                  SyncMessage.fromJson(json) ?? Message.fromJson(json),
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
    required Transport Function() transportFactory,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    Duration? pingInterval,
    Duration? pingTimeout,
    int? maxBufferSize,
    super.plugins,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast()
              ..add(ConnectionStatus.disconnected),
        _connectionStatusValue = ConnectionStatus.disconnected,
        _pingInterval = pingInterval ?? Protocol.pingInterval,
        _pingTimeout = pingTimeout ?? Protocol.pingTimeout,
        _maxBufferSize = maxBufferSize ?? Protocol.maxBufferSize,
        _handshakeGate = HandshakeGate(),
        _transportFactory = transportFactory {
    _syncManager = SyncManager(document: document, client: this);
    _messageCodec = CompressedCodec<Message>(
      PluginAwareMessageCodec.fromPlugins(
        plugins: plugins,
        defaultCodec: messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: (json) =>
                  SyncMessage.fromJson(json) ?? Message.fromJson(json),
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

  /// Incoming (transporter) messages controller
  final StreamController<Message> _messageController;

  /// Connection status controller
  final StreamController<ConnectionStatus> _connectionStatusController;
  ConnectionStatus _connectionStatusValue;

  final Transport Function() _transportFactory;

  /// Number of reconnect attempts
  int _reconnectAttempts = 0;

  /// If client is reconnecting
  bool _isReconnecting = false;

  /// Timer for periodic ping
  Timer? _pingTimer;

  /// Interval between outgoing pings
  final Duration _pingInterval;

  /// Maximum time to wait for a pong before considering the connection dead
  final Duration _pingTimeout;

  /// Maximum outbound buffer size (bytes) before the connection is torn down
  final int _maxBufferSize;

  /// Bounded, serialized outbound send queue for the current connection.
  ///
  /// Recreated on each [connect] (the transport is recreated too) and cleared
  /// on [disconnect].
  OutboundQueue? _outboundQueue;

  /// Timestamp of the last pong received from the server.
  ///
  /// Reset on connect and cleared on disconnect. Used to detect a half-open
  /// connection (one where sends still appear to succeed but the peer is gone).
  DateTime? _lastPongAt;

  /// Coordinates the handshake lifecycle (completer, timeout race, reset).
  final HandshakeGate _handshakeGate;

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

    if (_handshakeGate.inProgress) {
      // already under connection
      return _handshakeGate.pending!;
    }

    try {
      await tryCatchIgnore(() async {
        await _transport?.close();
      });

      _transport = _transportFactory();
      _outboundQueue = OutboundQueue(
        onSend: (data) => _transport!.send(data),
        maxBufferSize: _maxBufferSize,
      );

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
        // Seed liveness so a fresh connection is not immediately judged dead.
        _lastPongAt = DateTime.now();
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
    _sessionId = null;
    _lastPongAt = null;
    _outboundQueue?.close();
    _outboundQueue = null;

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

    // Only allow handshake and pong messages to be sent
    // before handshake is completed
    final isHandshakeOrPong = message.type == MessageType.handshakeRequest ||
        message.type == MessageType.pong;

    if (!isHandshakeOrPong && !await _handshakeGate.completed) {
      // If handshake is not completed, wait or skip the message
      throw StateError('Handshake not completed');
    }

    final data = _messageCodec.encode(message);

    // ignore: prefer_asserts_with_message assert function
    assert(() {
      if (data == null) {
        throw StateError(
          '[WebSocketClient] cannot send a message of type ${message.type}'
          ' that cannot be encoded.'
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
      await (_outboundQueue?.add(data) ?? _transport!.send(data));

      if (await _handshakeGate.completed) {
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
      final message = SyncMessage.change(
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

  /// Handle a single incoming transport frame.
  ///
  /// The WebSocket transport preserves message boundaries: each frame is
  /// exactly one encoded [Message]. We therefore decode each frame
  /// independently. A frame that cannot be decoded (malformed, or a plugin
  /// message this client does not understand) is dropped — it must never
  /// poison the decoding of subsequent frames.
  void _handleIncomingData(List<int> data) {
    // The client may be disposed (or reconnecting) while a frame is still in
    // flight from the transport. Dropping it is expected teardown behavior,
    // not an error, so bail out before decoding or asserting.
    if (_messageController.isClosed) {
      return;
    }

    Message? message;
    try {
      message = _messageCodec.decode(data);
    } catch (_) {
      // Undecodable frame: drop it and keep processing later frames.
      return;
    }

    // ignore: prefer_asserts_with_message assert function
    assert(() {
      if (message == null) {
        final type = Message.getTypeOrNull(data);
        throw StateError(
          '[WebSocketClient] received a message'
          '${type != null ? ' of type $type' : ''}'
          ' that cannot be decoded.'
          ' Have you added the plugin to the client?'
          '\nFrame: ${data.join(', ')}',
        );
      }
      return true;
    }());

    if (message != null) {
      _messageController.add(message);
    }
  }

  /// set status with [ConnectionStatus.error]
  /// and attempt to reconnect ([_attemptReconnect])
  void _handleTransportError(
    dynamic error, {
    bool attemptReconnect = true,
  }) {
    if (_handshakeGate.isActive) {
      _handshakeGate.reset();
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

  /// Start the periodic ping [_sendPing] with [_pingInterval] interval
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(
      _pingInterval,
      (_) => _sendPing(),
    );
  }

  /// Stop the periodic ping.
  ///
  /// Note: this only cancels the timer. The liveness timestamp
  /// ([_lastPongAt]) is owned by [connect]/[disconnect] so that restarting the
  /// timer does not wipe a freshly seeded value.
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send a ping message to the server.
  ///
  /// Before sending, detect a dead (half-open) connection: if no pong has been
  /// received within [_pingTimeout], the peer is gone even though sends may
  /// still appear to succeed. Route this through [_handleTransportError] so the
  /// existing reconnect machinery (status transitions, [Protocol
  /// .maxReconnectAttempts]) is reused.
  Future<void> _sendPing() async {
    if (_connectionStatusValue.isDisconnected) {
      return;
    }

    final lastPongAt = _lastPongAt;
    if (lastPongAt != null &&
        DateTime.now().difference(lastPongAt) > _pingTimeout) {
      _handleTransportError(
        TimeoutException('No pong received within $_pingTimeout'),
      );
      return;
    }

    await tryCatchIgnore(() async {
      final pingMessage = Message.ping(
        documentId: document.documentId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        // Report our version vector so the server can coordinate snapshots
        // once every client has confirmed a common frontier.
        versionVector: document.getVersionVector(),
      );
      await sendMessage(pingMessage);
    });
  }

  /// Performs the handshake with the server
  ///
  /// Returns true if the handshake is successful, false otherwise
  ///
  /// [Protocol.handshakeTimeout] is the maximum time to wait
  /// for the handshake response
  ///
  /// Handshake is not attempted to reconnect
  Future<bool> _performHandshake() {
    final handshakeRequest = HandshakeRequestMessage(
      versionVector: document.getVersionVector(),
      documentId: document.documentId,
      author: author,
    );

    return _handshakeGate.perform(
      // do not attempt to reconnect on handshake error
      // because the reconnect will handle it.
      send: () => sendMessage(handshakeRequest, attemptReconnect: false),
      timeout: Protocol.handshakeTimeout,
    );
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

      case MessageType.change:
        _handleChangeMessage(message as ChangeMessage);

      case MessageType.documentStatus:
        _handleDocumentStatusMessage(message as DocumentStatusMessage);

      case MessageType.ping:
        await _handlePingMessage(message as PingMessage);

      case MessageType.error:
        _handleErrorMessage(message as ErrorMessage);

      case MessageType.pong:
        _handlePongMessage(message as PongMessage);

      case MessageType.handshakeRequest:
      case MessageType.documentStatusRequest:
        break;
    }
  }

  /// Records that the server is alive.
  void _handlePongMessage(PongMessage message) {
    _lastPongAt = DateTime.now();
  }

  /// Handles the handshake response
  ///
  /// Completes the handshake and merges the changes
  /// and snapshot into the document
  void _handleHandshakeResponse(HandshakeResponseMessage message) {
    _sessionId = message.sessionId;

    // Complete the handshake first so that merge can send messages
    _handshakeGate.succeed();

    _syncManager.import(
      changes: message.changes,
      snapshot: message.snapshot,
      serverVersionVector: message.versionVector,
    );
  }

  void _handleChangeMessage(ChangeMessage message) {
    _syncManager.applyChange(message.change);
  }

  void _handleDocumentStatusMessage(DocumentStatusMessage message) {
    _syncManager.import(
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
        _handshakeGate.isActive) {
      _handshakeGate.reset();
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
