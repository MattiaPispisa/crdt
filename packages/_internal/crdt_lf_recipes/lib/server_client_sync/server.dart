// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion server
import 'dart:io';

import 'package:crdt_socket_sync/web_socket_server.dart';

/// Starts a sync server on [port] that hosts the note `notes`.
Future<WebSocketServer> startServer({int port = 8080}) async {
  final registry = InMemoryCRDTServerRegistry();

  // The server answers DOCUMENT_NOT_FOUND for a document it does not hold.
  await registry.addDocument('notes');

  final server = WebSocketServer(
    serverFactory: () => HttpServer.bind(InternetAddress.anyIPv4, port),
    serverRegistry: registry,
  );
  await server.start();
  return server;
}
// #enddocregion server

Future<void> main() async {
  final server = await startServer();
  stdout.writeln('Serving "notes" on ws://localhost:${server.port}');

  // #docregion stop
  // Ctrl+C closes every client session, then the HTTP server.
  await ProcessSignal.sigint.watch().first;
  await server.dispose();
  // #enddocregion stop
}
