import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/handshake_gate.dart';
import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/client/web_socket/channel_connector.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';
import 'package:crdt_socket_sync/src/relay/client/relay_client.dart';
import 'package:crdt_socket_sync/src/relay/client/relay_sync_manager.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';

/// {@template web_socket_relay_client}
/// [RelaySocketClient] implementation using web socket.
///
/// Reconnects with exponential backoff plus jitter
/// ([RelayProtocol.reconnectBaseDelay], doubled per attempt up to
/// [RelayProtocol.reconnectMaxDelay]) and, unlike `WebSocketClient`,
/// retries forever by default ([maxReconnectAttempts] can bound it).
/// {@endtemplate}
class WebSocketRelayClient extends RelaySocketClient {
  /// {@macro web_socket_relay_client}
  ///
  /// Constructor
  WebSocketRelayClient({
    required String url,
    required CRDTDocument document,
    required PeerId author,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    Duration? pingInterval,
    Duration? pingTimeout,
    Duration? handshakeTimeout,
    int? maxBufferSize,
    int? maxReconnectAttempts,
    Duration? reconnectBaseDelay,
    Duration? reconnectMaxDelay,
    Duration? reconnectJitter,
    List<ClientSyncPlugin>? plugins,
  }) : this._(
          url: url,
          document: document,
          author: author,
          transportFactory: null,
          compressor: compressor,
          messageCodec: messageCodec,
          pingInterval: pingInterval,
          pingTimeout: pingTimeout,
          handshakeTimeout: handshakeTimeout,
          maxBufferSize: maxBufferSize,
          maxReconnectAttempts: maxReconnectAttempts,
          reconnectBaseDelay: reconnectBaseDelay,
          reconnectMaxDelay: reconnectMaxDelay,
          reconnectJitter: reconnectJitter,
          plugins: plugins,
        );

  /// {@macro web_socket_relay_client}
  ///
  /// Constructor for testing
  WebSocketRelayClient.test({
    required String url,
    required CRDTDocument document,
    required PeerId author,
    required Transport Function() transportFactory,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    Duration? pingInterval,
    Duration? pingTimeout,
    Duration? handshakeTimeout,
    int? maxBufferSize,
    int? maxReconnectAttempts,
    Duration? reconnectBaseDelay,
    Duration? reconnectMaxDelay,
    Duration? reconnectJitter,
    Random? random,
    List<ClientSyncPlugin>? plugins,
  }) : this._(
          url: url,
          document: document,
          author: author,
          transportFactory: transportFactory,
          compressor: compressor,
          messageCodec: messageCodec,
          pingInterval: pingInterval,
          pingTimeout: pingTimeout,
          handshakeTimeout: handshakeTimeout,
          maxBufferSize: maxBufferSize,
          maxReconnectAttempts: maxReconnectAttempts,
          reconnectBaseDelay: reconnectBaseDelay,
          reconnectMaxDelay: reconnectMaxDelay,
          reconnectJitter: reconnectJitter,
          random: random,
          plugins: plugins,
        );

  WebSocketRelayClient._({
    required this.url,
    required this.document,
    required this.author,
    required Transport Function()? transportFactory,
    Compressor? compressor,
    MessageCodec<Message>? messageCodec,
    Duration? pingInterval,
    Duration? pingTimeout,
    Duration? handshakeTimeout,
    int? maxBufferSize,
    this.maxReconnectAttempts,
    Duration? reconnectBaseDelay,
    Duration? reconnectMaxDelay,
    Duration? reconnectJitter,
    Random? random,
    super.plugins,
  })  : _messageController = StreamController<Message>.broadcast(),
        _connectionStatusController =
            StreamController<ConnectionStatus>.broadcast()
              ..add(ConnectionStatus.disconnected),
        _connectionStatusValue = ConnectionStatus.disconnected,
        _pingInterval = pingInterval ?? Protocol.pingInterval,
        _pingTimeout = pingTimeout ?? Protocol.pingTimeout,
        _handshakeTimeout = handshakeTimeout ?? Protocol.handshakeTimeout,
        _maxBufferSize = maxBufferSize ?? Protocol.maxBufferSize,
        _reconnectBaseDelay =
            reconnectBaseDelay ?? RelayProtocol.reconnectBaseDelay,
        _reconnectMaxDelay =
            reconnectMaxDelay ?? RelayProtocol.reconnectMaxDelay,
        _reconnectJitter = reconnectJitter ?? RelayProtocol.reconnectJitter,
        _random = random ?? Random(),
        _handshakeGate = HandshakeGate(),
        _transportFactory = transportFactory ??
            (() => Transport.create(WebSocketChannelConnector(url))) {
    _syncManager = RelaySyncManager(document: document, client: this);
    _messageCodec = CompressedCodec<Message>(
      PluginAwareMessageCodec.fromPlugins(
        plugins: plugins,
        defaultCodec: messageCodec ??
            JsonMessageCodec<Message>(
              toJson: (message) => message.toJson(),
              fromJson: (json) =>
                  RelayMessage.fromJson(json) ?? Message.fromJson(json),
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

  /// WebSocket relay server URL
  final String url;

  /// Maximum reconnect attempts, `null` retries forever.
  final int? maxReconnectAttempts;

  /// Session ID
  String? _sessionId;

  @override
  String? get sessionId => _sessionId;

  /// Sync manager
  late final RelaySyncManager _syncManager;

  @override
  int get pendingChangesCount => _syncManager.pendingChangesCount;

  @override
  int get lastKnownSeq => _syncManager.lastKnownSeq;

  /// Transport for communication
  Transport? _transport;

  /// Incoming (transporter) messages controller
  final StreamController<Message> _messageController;

  /// Connection status controller
  final StreamController<ConnectionStatus> _connectionStatusController;
  ConnectionStatus _connectionStatusValue;

  final Transport Function() _transportFactory;

  /// Base delay of the exponential reconnect backoff
  final Duration _reconnectBaseDelay;

  /// Maximum delay of the exponential reconnect backoff
  final Duration _reconnectMaxDelay;

  /// Maximum random jitter added to every reconnect delay
  final Duration _reconnectJitter;

  /// Randomness for the reconnect jitter
  final Random _random;

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

  /// Maximum time to wait for the welcome after sending the hello.
  ///
  /// Injectable because some relay hosts (e.g. serverless runtimes with
  /// cold starts) may need more headroom than the default.
  final Duration _handshakeTimeout;

  /// Maximum outbound buffer size (bytes) before the connection is torn down
  final int _maxBufferSize;

  /// Bounded, serialized outbound send queue for the current connection.
  ///
  /// Recreated on each [connect] (the transport is recreated too) and cleared
  /// on [disconnect].
  OutboundQueue? _outboundQueue;

  /// Timestamp of the last pong received from the relay.
  ///
  /// Reset on connect and cleared on disconnect. Used to detect a half-open
  /// connection (one where sends still appear to succeed but the peer is
  /// gone).
  DateTime? _lastPongAt;

  /// Coordinates the join lifecycle (completer, timeout race, reset).
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

  /// Connect to the relay
  ///
  /// Returns true if the connection is successful, false otherwise
  ///
  /// 1. Setup the [Transport] for the connection
  /// 1. Start listening for incoming data
  /// 1. Join the room (hello/welcome exchange)
  /// 1. Start the ping timer
  ///
  /// If the join is successful then incoming messages are handled
  /// by [messages] stream.
  ///
  /// If the join fails then the client will attempt to reconnect.
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

      final connected = await _performJoin();
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

    _syncManager.onConnectionLost();

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

  /// Send a message to the relay
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

    // Only allow hello and pong messages to be sent
    // before the join is completed
    final isHelloOrPong = message.type == RelayMessageType.relayHello ||
        message.type == MessageType.pong;

    if (!isHelloOrPong && !await _handshakeGate.completed) {
      // If the join is not completed, wait or skip the message
      throw StateError('Handshake not completed');
    }

    final data = _messageCodec.encode(message);

    // ignore: prefer_asserts_with_message assert function
    assert(() {
      // TODO(m.pispisa): decifriamo il type se possibile
      if (data == null) {
        throw StateError(
          '[WebSocketRelayClient] cannot send a message that cannot be'
          ' encoded. Have you added the plugin to the client?'
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

  /// Enqueue [change] for the relay.
  ///
  /// The change is delivered at-least-once: it leaves the queue only when
  /// the relay acknowledges it, surviving reconnects in between.
  @override
  Future<void> sendChange(Change change) async {
    _syncManager.enqueue(change);
  }

  @override
  Future<void> requestSync() async {
    await _syncManager.requestState();
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
          '[WebSocketRelayClient] received a message'
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

    _syncManager.onConnectionLost();

    // on reconnecting if an error occurs do not update the status
    // to error, because the reconnect will handle it.
    if (!_isReconnecting) {
      _updateConnectionStatus(ConnectionStatus.error);
    }
    if (attemptReconnect) {
      _attemptReconnect();
    }
  }

  /// The delay before the next reconnect attempt
  /// ([RelayProtocol.reconnectDelay]).
  Duration _reconnectDelay() {
    return RelayProtocol.reconnectDelay(
      _reconnectAttempts,
      baseDelay: _reconnectBaseDelay,
      maxDelay: _reconnectMaxDelay,
      jitter: _reconnectJitter,
      random: _random,
    );
  }

  /// Attempt to reconnect, calling [connect] after [_reconnectDelay].
  ///
  /// Retries forever unless [maxReconnectAttempts] is set.
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) {
      return;
    }

    _isReconnecting = true;

    final maxAttempts = maxReconnectAttempts;
    if (maxAttempts != null && _reconnectAttempts >= maxAttempts) {
      _updateConnectionStatus(ConnectionStatus.error);
      _isReconnecting = false;
      return;
    }

    final delay = _reconnectDelay();
    _reconnectAttempts++;
    _updateConnectionStatus(ConnectionStatus.reconnecting);

    await Future<void>.delayed(delay);

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
  /// ([_lastPongAt]) is owned by [connect]/[disconnect] so that restarting
  /// the timer does not wipe a freshly seeded value.
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send a ping message to the relay.
  ///
  /// Before sending, detect a dead (half-open) connection: if no pong has
  /// been received within [_pingTimeout], the peer is gone even though sends
  /// may still appear to succeed. Route this through [_handleTransportError]
  /// so the existing reconnect machinery is reused.
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
      // Unlike the CRDT-aware protocol, no version vector is reported:
      // the relay could not interpret it.
      final pingMessage = Message.ping(
        documentId: document.documentId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await sendMessage(pingMessage);
    });
  }

  /// Joins the room: sends a hello and waits for the welcome.
  ///
  /// Returns true if the join is successful, false otherwise.
  ///
  /// [_handshakeTimeout] is the maximum time to wait for the welcome.
  Future<bool> _performJoin() {
    final hello = RelayHelloMessage(
      documentId: document.documentId,
      author: author,
    );

    return _handshakeGate.perform(
      // do not attempt to reconnect on join error
      // because the reconnect will handle it.
      send: () => sendMessage(hello, attemptReconnect: false),
      timeout: _handshakeTimeout,
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

    if (message is RelayWelcomeMessage) {
      return _handleWelcome(message);
    }
    if (message is RelayAckMessage) {
      return _syncManager.onAck(message);
    }
    if (message is RelayChangesMessage) {
      return _syncManager.onChanges(message);
    }
    if (message is PingMessage) {
      return _handlePingMessage(message);
    }
    if (message is PongMessage) {
      return _handlePongMessage(message);
    }
    if (message is ErrorMessage) {
      return _handleErrorMessage(message);
    }
  }

  /// Records that the relay is alive.
  void _handlePongMessage(PongMessage message) {
    _lastPongAt = DateTime.now();
  }

  /// Handles the welcome
  ///
  /// Completes the join and merges the served room state into the document.
  /// A welcome can also answer a [RelayStateRequestMessage] on an already
  /// joined connection: only the state import runs in that case.
  Future<void> _handleWelcome(RelayWelcomeMessage message) async {
    _sessionId = message.sessionId;

    // Complete the join first so that the sync manager can send messages
    _handshakeGate.succeed();

    await _syncManager.onWelcome(message);
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
