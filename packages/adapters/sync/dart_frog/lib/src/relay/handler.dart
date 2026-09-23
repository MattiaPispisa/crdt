import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync_dart_frog/src/common/web_socket_handler.dart';
import 'package:dart_frog/dart_frog.dart';

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
/// {@macro crdt_socket_sync_dart_frog.refuse_before_upgrade}
///
/// ```dart
/// Future<Response> onRequest(RequestContext context) async {
///   final token = context.request.headers[HttpHeaders.authorizationHeader];
///   if (!await isAuthorized(token)) {
///     return Response(statusCode: HttpStatus.unauthorized);
///   }
///   return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(
///     context,
///   );
/// }
/// ```
///
/// {@macro crdt_socket_sync_dart_frog.is_running}
///
/// The room (document id) travels inside the hello frame, not in the URL, so
/// one route serves every room.
///
/// {@macro crdt_socket_sync_dart_frog.ping_interval}
Handler crdtRelayWebSocketHandler(
  RelaySessionHost host, {
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
