import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/model/protocol.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';

enum SyncStatus { connecting, connected, reconnecting, disconnected }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Connects a [CRDTDocument] to a room on the signaling server.
///
/// All CRDT merge happens here on the client; the server is a dumb relay
/// (see `server/src/room.ts`). Local changes are queued as serialized blobs
/// and dropped only once the server acknowledges persistence, so a reconnect
/// can safely resend them (`importChanges` skips duplicates on every peer).
class SyncClient {
  SyncClient({
    required this.roomId,
    required this.document,
    required this.awareness,
    this.serverUrl = kServerUrl,
    ChannelFactory? channelFactory,
  }) : _connectChannel = channelFactory ?? WebSocketChannel.connect {
    awareness.outbound = _sendAwareness;
  }

  final String roomId;
  final CRDTDocument document;
  final AwarenessService awareness;
  final String serverUrl;
  final ChannelFactory _connectChannel;

  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.connecting);

  /// Local change blobs not yet acknowledged by the server.
  final List<Uint8List> _pending = [];

  /// How many blobs at the head of [_pending] are in the push in flight.
  int _inFlight = 0;

  WebSocketChannel? _channel;
  StreamSubscription<Change>? _localSub;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _handshaken = false;
  bool _disposed = false;
  final Random _random = Random();

  @visibleForTesting
  int get pendingCount => _pending.length;

  void connect() {
    if (_disposed) return;
    _localSub ??= document.localChanges.listen((change) {
      _pending.add(change.toBytes());
      _flush();
    });
    final uri = Uri.parse('$serverUrl/room/$roomId?client=${document.peerId}');
    try {
      _channel = _connectChannel(uri);
    } on Exception {
      _scheduleReconnect();
      return;
    }
    _socketSub = _channel!.stream.listen(
      _onFrame,
      onDone: _onSocketClosed,
      onError: (Object _) => _onSocketClosed(),
      cancelOnError: true,
    );
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    final ProtocolMessage? message;
    try {
      message = ProtocolMessage.decode(frame);
    } on FormatException {
      return;
    }
    switch (message) {
      case WelcomeMessage(
        :final snapshot,
        :final changes,
        :final seq,
        :final peers,
        :final compact,
      ):
        _handshaken = true;
        _reconnectAttempts = 0;
        status.value = SyncStatus.connected;
        document.import(
          snapshot: snapshot == null ? null : Snapshot.fromBytes(snapshot),
          changes: [for (final blob in changes) Change.fromBytes(blob)],
          merge: true,
          pruneHistory: false,
        );
        awareness.seedPeers(peers);
        awareness.republish();
        _inFlight = 0;
        _flush();
        if (compact) _uploadSnapshot(seq);
      case AckMessage(:final seq, :final compact):
        _pending.removeRange(0, min(_inFlight, _pending.length));
        _inFlight = 0;
        _flush();
        if (compact) _uploadSnapshot(seq);
      case ChangeMessage(:final changes):
        document.importChanges([
          for (final blob in changes) Change.fromBytes(blob),
        ]);
      case AwarenessMessage(:final from?, :final state):
        awareness.updatePeer(from, state);
      case PeerLeftMessage(:final clientId):
        awareness.removePeer(clientId);
      default:
        break;
    }
  }

  void _flush() {
    if (!_handshaken || _inFlight > 0 || _pending.isEmpty) return;
    _inFlight = _pending.length;
    _send(PushMessage(changes: List.of(_pending)));
  }

  void _uploadSnapshot(int upto) {
    final snapshot = document.takeSnapshot(pruneHistory: false);
    _send(SnapshotMessage(snapshot: snapshot.toBytes(), upto: upto));
  }

  void _sendAwareness(Map<String, dynamic> state) {
    if (!_handshaken) return;
    _send(AwarenessMessage(state: state));
  }

  void _send(ProtocolMessage message) {
    _channel?.sink.add(message.encode());
  }

  void _onSocketClosed() {
    if (_disposed) return;
    _handshaken = false;
    _inFlight = 0;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || (_reconnectTimer?.isActive ?? false)) return;
    status.value = SyncStatus.reconnecting;
    final backoff = min(500 * pow(2, _reconnectAttempts).toInt(), 10000);
    final jitter = _random.nextInt(250);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(milliseconds: backoff + jitter), () {
      _closeSocket();
      connect();
    });
  }

  void _closeSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    status.value = SyncStatus.disconnected;
    _reconnectTimer?.cancel();
    _localSub?.cancel();
    _closeSocket();
    status.dispose();
  }
}
