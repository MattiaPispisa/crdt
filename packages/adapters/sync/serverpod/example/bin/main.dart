// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion route
import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync_serverpod/sync.dart';
import 'package:crdt_socket_sync_serverpod_example/src/host.dart';
import 'package:crdt_socket_sync_serverpod_example/src/server_protocol.dart';
import 'package:serverpod/serverpod.dart';

/// The token a client sends. Replace it with a real check.
const exampleToken = 'example-token';

/// Server–client mode: the server holds the document, validates the changes
/// and takes aligned snapshots.
///
/// Connect with `WebSocketClient` at
/// `ws://localhost:8080/sync?token=example-token`.
/// The token travels in the query: `WebSocketClient` sends no headers, and a
/// browser cannot set them on a WebSocket. A caller without the token gets an
/// ordinary 401 and never reaches the protocol.
class ExampleSyncRoute extends CrdtSyncRoute {
  ExampleSyncRoute(super.sessionHost);

  @override
  FutureOr<Result> handleCall(Session session, Request request) {
    if (request.url.queryParameters['token'] != exampleToken) {
      return Response.unauthorized();
    }

    return super.handleCall(session, request);
  }
}

ServerConfig _serverConfig(int port) {
  return ServerConfig(
    port: port,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: port,
  );
}

/// Serves the host of [example] on `/sync` of the web server at [webPort],
/// and disposes it when the pod shuts down. The API server, at [apiPort], has
/// no endpoints in this example.
///
/// Serverpod handles `SIGINT`/`SIGTERM` itself. Its shutdown tasks run after
/// the web server has stopped, so no new client arrives while the host
/// closes; with a durable registry that is what flushes the writes still
/// waiting.
Future<Serverpod> startServer(
  List<String> args,
  ExampleHost example, {
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
  pod.webServer.addRoute(ExampleSyncRoute(example.host), '/sync');
  pod.experimental.shutdownTasks.addTask('crdt sync host', () async {
    await example.dispose();
    stdout.writeln('[sync] host disposed');
  });

  await example.host.start();
  await pod.start();
  return pod;
}
// #enddocregion route

/// Where the Hive database lives, relative to the working directory.
const _dbPath = 'db';

/// Opens the host and serves it.
Future<void> main(List<String> args) async {
  final example = await ExampleHost.open(dbPath: _dbPath);
  example.logEvents(stdout.writeln);
  final pod = await startServer(args, example);

  stdout.writeln(
    'sync ws://localhost:${pod.webServer.port}/sync ($exampleDocumentId)',
  );
}
