import 'dart:io';

import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:{{name}}_server/{{name}}_server.dart';

/// Starts the server on `PORT` (8080 by default) and keeps the documents in
/// `data/`.
///
/// Stops cleanly on Ctrl+C, so the last changes reach the storage.
Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await SyncServer.start(directory: 'data', port: port);

  server.events
      .where((event) => event.type == ServerEventType.error)
      .listen((event) => stderr.writeln('Error: ${event.message}'));
  stdout.writeln('Listening on ws://localhost:${server.port}');

  final signals = [
    ProcessSignal.sigint,
    // Windows cannot watch SIGTERM.
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  for (final signal in signals) {
    signal.watch().listen((_) async {
      await server.stop();
      exit(0);
    });
  }
}
