import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:crdt_socket_sync/src/common/common/web_socket_channel_connection.dart';
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
