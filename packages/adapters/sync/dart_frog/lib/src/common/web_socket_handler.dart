import 'package:crdt_socket_sync/server.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';

/// A Dart Frog [Handler] that upgrades the request and hands the channel to
/// [host].
Handler hostWebSocketHandler(
  SessionHostServer<ClientSession> host, {
  required Iterable<String>? protocols,
  required Iterable<String>? allowedOrigins,
  required Duration? pingInterval,
}) {
  return webSocketHandler(
    (channel, protocol) {
      // The 101 has already been sent, so a refusal has no status code left
      // to carry: the host closes the channel and returns null, and there is
      // nothing to do with it. A route refuses before calling this.
      host.acceptConnection(WebSocketChannelConnection(channel));
    },
    protocols: protocols,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );
}
