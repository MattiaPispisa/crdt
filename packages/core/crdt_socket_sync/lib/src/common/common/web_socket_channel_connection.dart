import 'package:crdt_socket_sync/src/common/common/transporter.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';
import 'package:web_socket_channel/status.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// [TransportConnection] over a [WebSocketChannel].
///
/// Works on both ends of the wire: a client channel opened with
/// [WebSocketChannel.connect], and a server channel handed over by an HTTP
/// framework that already performed the upgrade (`shelf_web_socket`,
/// `dart_frog_web_socket`, ...). A server-side channel arrives connected, so
/// nothing here waits on [WebSocketChannel.ready] — the caller does that when
/// it opened the channel itself.
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
