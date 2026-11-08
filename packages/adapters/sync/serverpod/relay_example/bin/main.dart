// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion server
import 'dart:io';

import 'package:crdt_socket_sync_serverpod/relay.dart';
import 'package:crdt_socket_sync_serverpod_relay_example/src/host.dart';
import 'package:crdt_socket_sync_serverpod_relay_example/src/server_protocol.dart';
import 'package:serverpod/serverpod.dart';

ServerConfig _serverConfig(int port) {
  return ServerConfig(
    port: port,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: port,
  );
}

/// Starts the relay host, serves it on `/relay` of the web server at
/// [webPort] and disposes it when the pod shuts down. The API server, at
/// [apiPort], has no endpoints in this example.
///
/// Relay mode: the server rebroadcasts opaque CRDT blobs to the other clients
/// of a room and persists them, without ever reading them. The room is the
/// document id inside the hello frame, not part of the path.
///
/// Serverpod handles `SIGINT`/`SIGTERM` itself. Its shutdown tasks run after
/// the web server has stopped, so no new client arrives while the host closes.
/// To authenticate, subclass [CrdtRelayRoute] the way `../example` does.
Future<Serverpod> startServer(
  List<String> args, {
  int webPort = 8080,
  int apiPort = 8081,
}) async {
  final pod = Serverpod(
    args,
    // Local to this example: a real project passes its own generated
    // `Protocol()` and `Endpoints()`.
    EmptyProtocol(),
    NoEndpoints(),
    config: ServerpodConfig(
      apiServer: _serverConfig(apiPort),
      webServer: _serverConfig(webPort),
    ),
  );
  pod.webServer.addRoute(CrdtRelayRoute(relayHost), '/relay');
  pod.experimental.shutdownTasks.addTask('crdt relay host', () async {
    await relayHost.dispose();
    stdout.writeln('[relay] host disposed');
  });

  await relayHost.start();
  await pod.start();
  return pod;
}
// #enddocregion server

Future<void> main(List<String> args) async {
  logRelayEvents(stdout.writeln);
  final pod = await startServer(args);

  stdout.writeln('relay ws://localhost:${pod.webServer.port}/relay');
}
