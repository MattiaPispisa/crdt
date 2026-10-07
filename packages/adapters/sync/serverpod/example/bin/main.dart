import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync_serverpod/sync.dart';
import 'package:crdt_socket_sync_serverpod_example/src/host.dart';
import 'package:crdt_socket_sync_serverpod_example/src/server_protocol.dart';
import 'package:serverpod/serverpod.dart';

/// Where the Hive database lives, relative to the working directory.
const _dbPath = 'db';

/// The port of the web server, which serves `/sync`.
const _webPort = 8080;

/// The port of the API server. This example has no endpoints on it.
const _apiPort = 8081;

/// Server–client mode: the server holds the document, validates the changes
/// and takes aligned snapshots.
///
/// The token check shows the point of doing this in the route: the request is
/// available *before* the socket exists, so a client that fails it gets an
/// ordinary 401 and never reaches the protocol. A request without an
/// `Authorization` header passes too; drop that to make the token required.
class ExampleSyncRoute extends CrdtSyncRoute {
  ExampleSyncRoute(super.sessionHost);

  @override
  FutureOr<Result> handleCall(Session session, Request request) {
    final hasToken = request.headers.authorization != null;
    if (hasToken && !session.isUserSignedIn) {
      return Response.unauthorized();
    }

    return super.handleCall(session, request);
  }
}

/// Accepts `Authorization: Bearer example-token`. Replace it with a real
/// check, or with the handler of `serverpod_auth`.
///
/// Serverpod needs a handler for any request that carries the header: without
/// one, the request fails with a 500 before the route runs.
Future<AuthenticationInfo?> _authenticate(Session session, String token) async {
  if (token != 'example-token') {
    return null;
  }
  return AuthenticationInfo('example-user', {}, authId: token);
}

ServerConfig _serverConfig(int port) {
  return ServerConfig(
    port: port,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: port,
  );
}

/// Opens the host, serves it on `/sync` and disposes it when the pod shuts
/// down.
///
/// Serverpod handles `SIGINT`/`SIGTERM` itself. Its shutdown tasks run after
/// the web server has stopped, so no new client arrives while the host
/// closes; with a durable registry that is what flushes the writes still
/// waiting.
Future<void> main(List<String> args) async {
  final example = await ExampleHost.open(dbPath: _dbPath);
  example.logEvents(stdout.writeln);

  final pod = Serverpod(
    args,
    EmptyProtocol(),
    NoEndpoints(),
    authenticationHandler: _authenticate,
    config: ServerpodConfig(
      apiServer: _serverConfig(_apiPort),
      webServer: _serverConfig(_webPort),
    ),
  );
  pod.webServer.addRoute(ExampleSyncRoute(example.host), '/sync');
  pod.experimental.shutdownTasks.addTask('crdt sync host', () async {
    await example.dispose();
    stdout.writeln('[sync] host disposed');
  });

  await example.host.start();
  await pod.start();

  stdout.writeln('sync ws://localhost:$_webPort/sync ($exampleDocumentId)');
}
