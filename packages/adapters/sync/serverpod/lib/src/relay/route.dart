import 'dart:async';

import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync_serverpod/src/common/web_socket_upgrade.dart';
import 'package:serverpod/serverpod.dart';

/// A Serverpod [Route] that upgrades the request and hands the socket to
/// [sessionHost], the relay ([RelaySessionHost]) side of the protocol.
///
/// ```dart
/// pod.webServer.addRoute(CrdtRelayRoute(relayHost), '/relay');
/// ```
///
/// {@macro crdt_socket_sync_serverpod.refuse_before_upgrade}
///
/// ```dart
/// class AuthRelayRoute extends CrdtRelayRoute {
///   AuthRelayRoute(super.sessionHost);
///
///   @override
///   FutureOr<Result> handleCall(Session session, Request request) {
///     if (!session.isUserSignedIn) {
///       return Response.unauthorized();
///     }
///     return super.handleCall(session, request);
///   }
/// }
/// ```
///
/// {@macro crdt_socket_sync_serverpod.session_scope}
///
/// The room (document id) travels inside the hello frame, not in the URL, so
/// one route serves every room.
class CrdtRelayRoute extends Route {
  /// {@macro crdt_socket_sync_serverpod.route_options}
  CrdtRelayRoute(
    this.sessionHost, {
    this.pingInterval,
    this.allowAnyOrigin = false,
    super.methods,
    super.path,
    super.host,
  });

  /// The host that takes the upgraded sockets.
  final RelaySessionHost sessionHost;

  /// The WebSocket-level ping interval; `null` for Relic's default.
  final Duration? pingInterval;

  /// Whether a cross-origin upgrade is accepted.
  final bool allowAnyOrigin;

  @override
  FutureOr<Result> handleCall(Session session, Request request) {
    return hostWebSocketUpgrade(
      sessionHost,
      pingInterval: pingInterval,
      allowAnyOrigin: allowAnyOrigin,
    );
  }
}
