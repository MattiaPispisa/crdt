// ignore_for_file: avoid_print just an example

import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync/src/server/in_memory_server_registry.dart'
    as r;
import 'package:crdt_socket_sync/src/web_socket_server.dart';

import 'hot_reload_wathcer.dart';

late WebSocketServer server;

void main(List<String> args) async {
  print('🚀 Starting CRDT WebSocket Server...');

  server = WebSocketServer(
    host: 'localhost',
    port: 8080,
    documentRegistry: r.InMemoryCRDTServerRegistry(),
  );

  _setupSigintHandler();
  await _startServer();
  await _watch();
}

void _setupSigintHandler() {
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⏹️  Received SIGINT, shutting down gracefully...');
    await server.stop();
    print('✅ Server stopped.');
    exit(0);
  });
}

Future<void> _watch() {
  final watcher = HotReloadWatcher(
    watchPaths: [
      'lib',
      'example',
      '../crdt_lf/lib',
    ],
    debounceDelay: const Duration(milliseconds: 300),
  )..onFileChanged = _restartServer;
  return watcher.startWatching();
}

Future<void> _restartServer() async {
  print('🔄 Files changed, restarting server...');
  await server.stop();
  print('⏹️  Server stopped for hot reload');
  return _startServer();
}

Future<void> _startServer() async {
  try {
    await server.start();
    print('✅ CRDT WebSocket Server started successfully!');
    print('📡 Listening on port ${server.port}');
    print('💡 Press Ctrl+C to stop the server');

    // Keep the server running indefinitely
    print('🔄 Server is running... waiting for connections');

    server.serverEvents.listen((event) {
      print('➡ Server event: $event');
    });

    return;
  } catch (e) {
    print('❌ Failed to start server: $e');
    exit(1);
  }
}
