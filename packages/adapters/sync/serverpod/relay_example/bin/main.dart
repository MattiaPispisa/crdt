import 'dart:io';

import 'package:crdt_socket_sync_serverpod/relay.dart';
import 'package:crdt_socket_sync_serverpod_relay_example/src/host.dart';
import 'package:crdt_socket_sync_serverpod_relay_example/src/server_protocol.dart';
import 'package:serverpod/serverpod.dart';

/// The port of the web server, which serves `/relay`.
const _webPort = 8080;

/// The port of the API server. This example has no endpoints on it.
const _apiPort = 8081;

ServerConfig _serverConfig(int port) {
  return ServerConfig(
    port: port,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: port,
  );
}

/// Starts the relay host, serves it on `/relay` and disposes it when the pod
/// shuts down.
///
/// Relay mode: the server rebroadcasts opaque CRDT blobs to the other clients
/// of a room and persists them, without ever reading them. The room is the
/// document id inside the hello frame, not part of the path.
///
/// Serverpod handles `SIGINT`/`SIGTERM` itself. Its shutdown tasks run after
/// the web server has stopped, so no new client arrives while the host closes.
/// To authenticate, subclass [CrdtRelayRoute] the way `../example` does.
Future<void> main(List<String> args) async {
  logRelayEvents(stdout.writeln);

  final pod = Serverpod(
    args,
    EmptyProtocol(),
    NoEndpoints(),
    config: ServerpodConfig(
      apiServer: _serverConfig(_apiPort),
      webServer: _serverConfig(_webPort),
    ),
  );
  pod.webServer.addRoute(CrdtRelayRoute(relayHost), '/relay');
  pod.experimental.shutdownTasks.addTask('crdt relay host', () async {
    await relayHost.dispose();
    stdout.writeln('[relay] host disposed');
  });

  await relayHost.start();
  await pod.start();

  stdout.writeln('relay ws://localhost:$_webPort/relay');
}
