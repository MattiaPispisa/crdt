import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:greyhound_markdown_server_dart_frog/src/host.dart';

/// Starts [relayHost] and disposes it on `SIGINT`/`SIGTERM`.
///
/// Here and not in [run]: `dart_frog dev` calls [run] again on every hot
/// reload.
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

/// Serves the handler Dart Frog built.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  stdout.writeln('relay ws://localhost:$port/room/<id>');

  return serve(handler, ip, port);
}
