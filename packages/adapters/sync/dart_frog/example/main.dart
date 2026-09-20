import 'dart:io';

import 'package:crdt_socket_sync_dart_frog_example/src/hosts.dart';
import 'package:dart_frog/dart_frog.dart';

/// Custom init: runs once, before Dart Frog builds the handler tree.
///
/// Starts the hosts and disposes them on `SIGINT`/`SIGTERM`. Dart Frog has no
/// shutdown hook, so the signals are where an orderly teardown goes; with a
/// durable registry that is what flushes the writes still waiting.
///
/// Not in [run]: `dart_frog dev` calls [run] again on every hot reload, so a
/// listener registered there piles up one copy per reload.
Future<void> init(InternetAddress ip, int port) async {
  hosts.logEvents(stdout.writeln);
  await hosts.start();

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await hosts.dispose();
      exit(0);
    });
  }
}

/// Custom entrypoint: serves the handler Dart Frog built.
///
/// The hosts are already up by now — see [init].
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  stdout.writeln('sync  ws://${ip.address}:$port/sync  ($exampleDocumentId)');
  stdout.writeln('relay ws://${ip.address}:$port/relay');

  return serve(handler, ip, port);
}
