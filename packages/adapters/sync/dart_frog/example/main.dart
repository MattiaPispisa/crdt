import 'dart:io';

import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Where the Hive database lives, relative to the project directory
/// `dart_frog dev` runs in.
const _dbPath = 'db';

/// Custom init: runs once, before Dart Frog builds the handler tree.
///
/// Opens the database, starts the host and disposes it on `SIGINT`/`SIGTERM`.
/// Dart Frog has no shutdown hook, so the signals are where an orderly
/// teardown goes; with a durable registry that is what flushes the writes
/// still waiting.
///
/// Not in [run]: `dart_frog dev` calls [run] again on every hot reload, so a
/// listener registered there piles up one copy per reload.
Future<void> init(InternetAddress ip, int port) async {
  example = await ExampleHost.open(dbPath: _dbPath);
  example.logEvents(stdout.writeln);
  await example.host.start();

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await example.dispose();
      exit(0);
    });
  }
}

/// Custom entrypoint: serves the handler Dart Frog built.
///
/// The host is already up by now — see [init].
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  stdout.writeln('sync ws://${ip.address}:$port/sync ($exampleDocumentId)');

  return serve(handler, ip, port);
}
