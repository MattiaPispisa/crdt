import 'dart:io';

import 'package:crdt_socket_sync/src/common/server/web_socket/io_host.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/transformer.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_client_session.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_session_host.dart';
import 'package:meta/meta.dart';

/// WebSocket server implementation.
///
/// A [DocumentSessionHost] that owns a `dart:io` [HttpServer]: it binds on
/// [start], upgrades every WebSocket request it receives and hands the socket
/// to the host. To serve the same protocol from an HTTP server you already
/// have (Dart Frog, shelf, ...), use [DocumentSessionHost] directly and call
/// `acceptConnection` yourself.
class WebSocketServer extends DocumentSessionHost
    with IoWebSocketHost<DocumentClientSession> {
  /// Constructor
  WebSocketServer({
    required Future<HttpServer> Function() serverFactory,
    required super.serverRegistry,
    super.compressor,
    super.messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer = DefaultWebSocketServerTransformer();

  /// Constructor for testing
  WebSocketServer.test({
    required Future<HttpServer> Function() serverFactory,
    required super.serverRegistry,
    super.compressor,
    WebSocketServerTransformer? serverTransformer,
    super.messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer =
            serverTransformer ?? DefaultWebSocketServerTransformer();

  final Future<HttpServer> Function() _serverFactory;

  final WebSocketServerTransformer _serverTransformer;

  @protected
  @override
  Future<HttpServer> Function() get serverFactory => _serverFactory;

  @protected
  @override
  WebSocketServerTransformer get serverTransformer => _serverTransformer;

  @protected
  @override
  String get debugLabel => 'WebSocketServer';

  @protected
  @override
  String get startedMessage => 'Server started on $host:$port';

  @protected
  @override
  String get stoppedMessage => 'Server stopped';
}
