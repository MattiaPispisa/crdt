import 'dart:io';

import 'package:crdt_socket_sync/src/common/server/web_socket/io_host.dart';
import 'package:crdt_socket_sync/src/common/server/web_socket/transformer.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_client_session.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_session_host.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';
import 'package:meta/meta.dart';

/// {@template web_socket_relay_server}
/// WebSocket relay server implementation.
///
/// A [RelaySessionHost] that owns a `dart:io` [HttpServer]: it binds on
/// [start], upgrades every WebSocket request it receives and hands the socket
/// to the host. To serve the relay protocol from an HTTP server you already
/// have (Dart Frog, shelf, ...), use [RelaySessionHost] directly and call
/// `acceptConnection` yourself.
///
/// A relay server rebroadcasts opaque CRDT change blobs to the other clients
/// of a room and persists them in a [RelayStore], without ever interpreting
/// CRDT data: merging is entirely a client concern. One server hosts many
/// rooms, keyed by document id.
/// {@endtemplate}
class WebSocketRelayServer extends RelaySessionHost
    with IoWebSocketHost<RelayClientSession> {
  /// {@macro web_socket_relay_server}
  ///
  /// Constructor
  WebSocketRelayServer({
    required Future<HttpServer> Function() serverFactory,
    super.store,
    super.compaction,
    super.compressor,
    super.messageCodec,
    super.maxBufferSize,
    super.plugins,
  })  : _serverFactory = serverFactory,
        _serverTransformer = DefaultWebSocketServerTransformer();

  /// {@macro web_socket_relay_server}
  ///
  /// Constructor for testing
  WebSocketRelayServer.test({
    required Future<HttpServer> Function() serverFactory,
    WebSocketServerTransformer? serverTransformer,
    super.store,
    super.compaction,
    super.compressor,
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
  String get debugLabel => 'WebSocketRelayServer';

  @protected
  @override
  String get startedMessage => 'Relay server started on $host:$port';
}
