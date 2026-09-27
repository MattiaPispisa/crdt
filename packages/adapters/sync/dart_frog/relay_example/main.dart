import 'dart:io';

import 'package:crdt_socket_sync_dart_frog_relay_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Custom init: runs once, before Dart Frog builds the handler tree.
///
/// Starts the host and disposes it on `SIGINT`/`SIGTERM`. Dart Frog has no
/// shutdown hook, so the signals are where an orderly teardown goes.
///
/// Not in [run]: `dart_frog dev` calls [run] again on every hot reload, so a
/// listener registered there piles up one copy per reload.
Future<void> init(InternetAddress ip, int port) async {
  logRelayEvents(stdout.writeln);
  await relayHost.start();

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await relayHost.dispose();
      exit(0);
    });
  }
}

/// Custom entrypoint: serves the handler Dart Frog built.
///
/// The host is already up by now — see [init].
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  stdout.writeln('relay ws://${ip.address}:$port/relay');

  return serve(handler, ip, port);
}
