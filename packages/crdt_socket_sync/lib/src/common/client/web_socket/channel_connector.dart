import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// [TransportConnector] that connects using [WebSocketChannel.connect].
class WebSocketChannelConnector implements TransportConnector {
  /// Constructor
  WebSocketChannelConnector(this.url);

  /// The WebSocket server URL
  final String url;

  @override
  Future<TransportConnection> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));

    await channel.ready;

    return WebSocketChannelConnection(channel);
  }
}

/// [TransportConnection] over a [WebSocketChannel].
class WebSocketChannelConnection implements TransportConnection {
  /// Constructor
  WebSocketChannelConnection(this._channel);

  /// The WebSocket channel
  final WebSocketChannel _channel;

  @override
  Stream<List<int>> get incoming {
    return _channel.stream.map(frameToBytes);
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
