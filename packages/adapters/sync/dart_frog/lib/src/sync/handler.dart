import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_dart_frog/src/common/web_socket_handler.dart';
import 'package:dart_frog/dart_frog.dart';

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
/// {@template crdt_socket_sync_dart_frog.refuse_before_upgrade}
/// Calling this completes the WebSocket upgrade. From then on the response is
/// a `101`, so a client the host will not take — stopped, disposed, or a
/// session id already in use — is hung up on, with no status code and no
/// reason. Refuse before the call to answer with one:
/// {@endtemplate}
///
/// ```dart
/// Future<Response> onRequest(RequestContext context) async {
///   final token = context.request.headers[HttpHeaders.authorizationHeader];
///   if (!await isAuthorized(token)) {
///     return Response(statusCode: HttpStatus.unauthorized);
///   }
///   return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(
///     context,
///   );
/// }
/// ```
///
/// {@template crdt_socket_sync_dart_frog.is_running}
/// The same window is where [SessionHostServer.isRunning] belongs, for a
/// shutdown that should answer `503` rather than accept a socket and close
/// it.
/// {@endtemplate}
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
  return hostWebSocketHandler(
    host,
    protocols: protocols,
    allowedOrigins: allowedOrigins,
    pingInterval: pingInterval,
  );
}
