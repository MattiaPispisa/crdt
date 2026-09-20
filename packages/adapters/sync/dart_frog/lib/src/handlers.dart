import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync/server.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';

/// A Dart Frog [Handler] that upgrades the request and hands the socket to
/// [host], the CRDT-aware ([DocumentSessionHost]) side of the protocol.
///
/// ```dart
/// // routes/sync.dart
/// Future<Response> onRequest(RequestContext context) async {
///   return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(
///     context,
///   );
/// }
/// ```
///
/// Because the upgrade happens inside a route, the [RequestContext] — headers,
/// cookies, whatever middleware put there — is available *before* the socket
/// exists. Authenticate there and return a [Response] instead of calling this,
/// and the client never reaches the protocol.
///
/// The document id travels inside the protocol's own frames, not in the URL,
/// so no route parameter is needed. A `routes/sync/[documentId].dart` route
/// still works and is the place to authorize per document.
///
/// {@template crdt_socket_sync_dart_frog.ping_interval}
/// [protocols], [allowedOrigins] and [pingInterval] are passed straight to
/// `dart_frog_web_socket`. [allowedOrigins] is the one to set for a browser
/// client: unset, any origin may connect.
///
/// [pingInterval] is a **WebSocket-level** ping, which is not the protocol's
/// own ping (`Protocol.pingInterval`, 15s, answered with a pong and carrying
/// the client's version vector). They serve different purposes — setting one
/// does not let you drop the other.
/// {@endtemplate}
Handler crdtSyncWebSocketHandler(
  DocumentSessionHost host, {
  Iterable<String>? protocols,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
}) {
  return _handlerFor(
    host,
    protocols: protocols,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );
}

/// A Dart Frog [Handler] that upgrades the request and hands the socket to
/// [host], the relay ([RelaySessionHost]) side of the protocol.
///
/// ```dart
/// // routes/relay.dart
/// Future<Response> onRequest(RequestContext context) async {
///   return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(
///     context,
///   );
/// }
/// ```
///
/// {@macro crdt_socket_sync_dart_frog.ping_interval}
Handler crdtRelayWebSocketHandler(
  RelaySessionHost host, {
  Iterable<String>? protocols,
  Iterable<String>? allowedOrigins,
  Duration? pingInterval,
}) {
  return _handlerFor(
    host,
    protocols: protocols,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );
}

/// Upgrades the request and hands the channel to [host].
Handler _handlerFor(
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
