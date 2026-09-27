import 'dart:io';

import 'package:crdt_socket_sync/src/common/server/client_session.dart';
import 'package:crdt_socket_sync/src/common/server/session_host.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/io_connection.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/transformer.dart';
import 'package:meta/meta.dart';

/// Gives a [SessionHostServer] a `dart:io` [HttpServer] of its own.
///
/// The host below it works on any transport; a host embedded in another HTTP
/// server does not mix this in and stays free of `dart:io`.
mixin IoWebSocketHost<S extends ClientSession> on SessionHostServer<S> {
  /// Creates the [HttpServer] this host serves on.
  @protected
  Future<HttpServer> Function() get serverFactory;

  /// Upgrades an [HttpRequest] to a [WebSocket].
  @protected
  WebSocketServerTransformer get serverTransformer;

  HttpServer? _httpServer;

  /// The server host; `''` while the server is not running.
  String get host => _httpServer?.address.host ?? '';

  /// The server port; `0` while the server is not running.
  int get port => _httpServer?.port ?? 0;

  @protected
  @override
  bool get ownsTransport => true;

  @protected
  @override
  Future<void> onStart() async {
    _httpServer = await serverFactory();
  }

  @protected
  @override
  Future<void> onStarted() async {
    _httpServer!.listen(_handleRequest);
  }

  @protected
  @override
  Future<void> onStop() async {
    await _httpServer?.close();
    _httpServer = null;
  }

  void _handleRequest(HttpRequest request) {
    if (serverTransformer.isUpgradeRequest(request)) {
      serverTransformer.upgrade(request).then(
            (webSocket) => acceptConnection(IoWebSocketConnection(webSocket)),
          );
    } else {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.close();
    }
  }
}
