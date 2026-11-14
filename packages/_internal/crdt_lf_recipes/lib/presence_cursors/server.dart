// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion server
import 'dart:io';

import 'package:crdt_socket_sync/web_socket_relay_server.dart';

/// Starts a relay on [port] that also shares the presence of each room.
Future<WebSocketRelayServer> startPresenceRelay({int port = 8080}) async {
  final server = WebSocketRelayServer(
    serverFactory: () => HttpServer.bind(InternetAddress.anyIPv4, port),
    // One instance per server: it keeps who is in which room.
    plugins: [ServerAwarenessPlugin()],
  );
  await server.start();
  return server;
}
// #enddocregion server

Future<void> main() async {
  final server = await startPresenceRelay();
  stdout.writeln('Relay on ws://localhost:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.dispose();
}
