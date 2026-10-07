import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_socket_sync/server.dart';
import 'package:serverpod/serverpod.dart';

const _normalClosure = 1000;

/// [TransportConnection] over a Relic [RelicWebSocket], the socket a
/// Serverpod `WebSocketUpgrade` hands over.
///
/// Text and binary frames both arrive as bytes on [incoming]. Sending on a
/// closed socket is a no-op.
class RelicWebSocketConnection implements TransportConnection {
  /// Wraps an already upgraded [RelicWebSocket].
  RelicWebSocketConnection(this._webSocket);

  final RelicWebSocket _webSocket;

  @override
  Stream<List<int>> get incoming async* {
    await for (final event in _webSocket.events) {
      switch (event) {
        case TextDataReceived(:final text):
          yield utf8.encode(text);
        case BinaryDataReceived(:final data):
          yield data;
        case CloseReceived():
          return;
      }
    }
  }

  @override
  Future<void> send(List<int> data) async {
    _webSocket.trySendBytes(Uint8List.fromList(data));
  }

  @override
  Future<void> close() async {
    await _webSocket.tryClose(_normalClosure);
  }

  @override
  bool get isConnected => !_webSocket.isClosed;
}
