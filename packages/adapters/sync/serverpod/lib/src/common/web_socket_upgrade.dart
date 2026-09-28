import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_serverpod/src/common/relic_web_socket_connection.dart';
import 'package:serverpod/serverpod.dart';

/// A [WebSocketUpgrade] that hands the upgraded socket to [host].
///
/// [pingInterval] replaces Relic's WebSocket ping interval; `null` keeps
/// Relic's default.
WebSocketUpgrade hostWebSocketUpgrade(
  SessionHostServer<ClientSession> host, {
  required Duration? pingInterval,
  required bool allowAnyOrigin,
}) {
  return WebSocketUpgrade((webSocket) {
    if (pingInterval != null) {
      webSocket.pingInterval = pingInterval;
    }
    // The 101 has already been sent, so a refusal has no status code left
    // to carry: the host closes the socket, and the null it returns is moot.
    host.acceptConnection(RelicWebSocketConnection(webSocket));
  }, allowAnyOrigin: allowAnyOrigin);
}
