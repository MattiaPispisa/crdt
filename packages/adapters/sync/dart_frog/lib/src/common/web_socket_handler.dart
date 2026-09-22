import 'package:crdt_socket_sync/server.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';

/// A Dart Frog [Handler] that upgrades the request and hands the channel to
/// [host].
///
/// Shared by both modes: the protocol is the host's business, the upgrade is
/// the same.
Handler hostWebSocketHandler(
  SessionHostServer<ClientSession> host, {
  required Iterable<String>? protocols,
  required Iterable<String>? allowedOrigins,
  required Duration? pingInterval,
}) {
  return webSocketHandler(
    (channel, protocol) {
      // A refusal returns null after closing the channel, which is all the
      // caller can do here: the response is already a 101.
      host.acceptConnection(WebSocketChannelConnection(channel));
    },
    protocols: protocols,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );
}
