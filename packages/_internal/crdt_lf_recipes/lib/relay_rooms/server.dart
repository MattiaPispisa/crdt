// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion server
import 'dart:io';

import 'package:crdt_socket_sync/web_socket_relay_server.dart';

/// Starts a relay server on [port]. Rooms are created on demand.
Future<WebSocketRelayServer> startRelay({int port = 8080}) async {
  // No registration: a client can join any room id.
  final server = WebSocketRelayServer(
    serverFactory: () => HttpServer.bind(InternetAddress.anyIPv4, port),
    // The default store keeps the rooms in memory: a restart loses them.
    store: InMemoryRelayStore(),
  );
  await server.start();
  return server;
}
// #enddocregion server

Future<void> main() async {
  final server = await startRelay();
  stdout.writeln('Relay on ws://localhost:${server.port}');

  // #docregion stop
  await ProcessSignal.sigint.watch().first;
  await server.dispose();
  // #enddocregion stop
}
