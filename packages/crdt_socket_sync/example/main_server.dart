// ignore_for_file: avoid_print just an example

import 'dart:async';
import 'dart:io';

import 'package:crdt_socket_sync/src/web_socket_server.dart';
import 'server_registry.dart';

late WebSocketServer server;

void main(List<String> args) async {
  print('🚀 Starting CRDT WebSocket Server...');

  server = WebSocketServer(
    host: 'localhost',
    port: 8080,
    serverRegistry: serverRegistry,
  );

  _setupSigintHandler();
  await _startServer();
}

void _setupSigintHandler() {
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⏹️  Received SIGINT, shutting down gracefully...');
    await server.stop();
    print('✅ Server stopped.');
    exit(0);
  });
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

    final completer = Completer<void>();
    await completer.future;
    return;
  } catch (e) {
    print('❌ Failed to start server: $e');
    exit(1);
  }
}
