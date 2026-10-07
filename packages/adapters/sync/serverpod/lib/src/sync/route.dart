import 'dart:async';

import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_serverpod/src/common/web_socket_upgrade.dart';
import 'package:serverpod/serverpod.dart';

/// A Serverpod [Route] that upgrades the request and hands the socket to
/// [sessionHost], the CRDT-aware ([DocumentSessionHost]) side of the
/// protocol.
///
/// ```dart
/// pod.webServer.addRoute(CrdtSyncRoute(syncHost), '/sync');
/// ```
///
/// {@template crdt_socket_sync_serverpod.refuse_before_upgrade}
/// [handleCall] completes the WebSocket upgrade. From then on the response is
/// a `101`, so a client the host will not take — stopped, disposed, or a
/// session id already in use — is hung up on, with no status code and no
/// reason. To answer with one, subclass the route and refuse before calling
/// `super.handleCall`:
/// {@endtemplate}
///
/// ```dart
/// class AuthSyncRoute extends CrdtSyncRoute {
///   AuthSyncRoute(super.sessionHost);
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
/// {@template crdt_socket_sync_serverpod.session_scope}
/// Serverpod closes the [Session] as soon as [handleCall] returns, before the
/// socket is handed over. Read what the check needs from it first.
/// {@endtemplate}
///
/// The document id travels inside the protocol's own frames, not in the URL,
/// so one route serves every document.
class CrdtSyncRoute extends Route {
  /// {@template crdt_socket_sync_serverpod.route_options}
  /// [pingInterval] is a **WebSocket-level** ping, which is not the
  /// protocol's own ping (`Protocol.pingInterval`); `null` keeps Relic's
  /// default. [allowAnyOrigin] lets a browser page on another host connect:
  /// by default a cross-origin upgrade gets a `403`.
  ///
  /// [methods], [path] and [host] are the ones of [Route].
  /// {@endtemplate}
  CrdtSyncRoute(
    this.sessionHost, {
    this.pingInterval,
    this.allowAnyOrigin = false,
    super.methods,
    super.path,
    super.host,
  });

  /// The host that takes the upgraded sockets.
  final DocumentSessionHost sessionHost;

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
