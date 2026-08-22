import 'dart:io';

import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:web_socket_channel/status.dart';

/// [TransportConnection] over a server-side **`dart:io`** [WebSocket].
class IoWebSocketConnection implements TransportConnection {
  /// Constructor
  IoWebSocketConnection(this._webSocket);

  /// The WebSocket
  final WebSocket _webSocket;

  @override
  Stream<List<int>> get incoming {
    return _webSocket.map(frameToBytes);
  }

  @override
  Future<void> send(List<int> data) async {
    _webSocket.add(data);
  }

  @override
  Future<void> close() async {
    await _webSocket.close(normalClosure);
  }

  @override
  bool get isConnected => _webSocket.readyState == WebSocket.open;
}
