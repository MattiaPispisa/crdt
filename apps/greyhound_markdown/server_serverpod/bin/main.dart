import 'dart:io';

import 'package:crdt_socket_sync_serverpod/relay.dart';
import 'package:greyhound_markdown_server_serverpod/src/host.dart';
import 'package:greyhound_markdown_server_serverpod/src/server_protocol.dart';
import 'package:serverpod/serverpod.dart';

/// The Worker's local port, so the client's default URL reaches this server.
const _webPort = 8787;

/// Serverpod always starts its API server; this one has no endpoints.
const _apiPort = 8788;

ServerConfig _serverConfig(int port) {
  return ServerConfig(
    port: port,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: port,
  );
}

/// Serves [relayHost] on `/room/<id>` until Serverpod shuts down.
///
/// Serverpod handles `SIGINT`/`SIGTERM` itself and runs the shutdown task
/// after the web server has stopped.
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
  // The client page is on another port, so the upgrade is cross-origin.
  pod.webServer.addRoute(
    CrdtRelayRoute(relayHost, allowAnyOrigin: true),
    '/room/:id',
  );
  pod.experimental.shutdownTasks.addTask('crdt relay host', () async {
    await relayHost.dispose();
    stdout.writeln('[relay] host disposed');
  });

  await relayHost.start();
  await pod.start();

  stdout.writeln('relay ws://localhost:$_webPort/room/<id>');
}
