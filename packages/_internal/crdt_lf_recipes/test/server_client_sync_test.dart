// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_recipes/server_client_sync/client.dart';
import 'package:crdt_lf_recipes/server_client_sync/server.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [text], in [document], reads [expected].
Future<void> waitForText(
  CRDTDocument document,
  CRDTFugueTextHandler text,
  String expected,
) async {
  if (text.value == expected) return;
  await document.updates
      .firstWhere((_) => text.value == expected)
      .timeout(const Duration(seconds: 5));
}

void main() {
  late WebSocketServer server;
  late String url;
  final clients = <WebSocketClient>[];

  setUp(() async {
    server = await startServer(port: 0); // port 0: any free port
    url = 'ws://localhost:${server.port}';
  });

  tearDown(() async {
    for (final client in clients) {
      await client.disconnect();
      client.dispose();
      client.document.dispose();
    }
    clients.clear();
    await server.dispose();
  });

  test('an edit on one client reaches the other', () async {
    final alice = await connectClient(url);
    final bob = await connectClient(url);
    clients.addAll([alice.client, bob.client]);

    expect(alice.client.connectionStatusValue, ConnectionStatus.connected);
    expect(bob.client.connectionStatusValue, ConnectionStatus.connected);

    alice.text.insert(0, 'Hello');
    await waitForText(bob.client.document, bob.text, 'Hello');

    bob.text.insert(5, ', world');
    await waitForText(alice.client.document, alice.text, 'Hello, world');
  });

  test('a client of an unregistered document is refused', () async {
    final statuses = <ConnectionStatus>[];
    final stranger = await connectClient(
      url,
      documentId: 'unknown',
      onStatus: statuses.add,
    );
    clients.add(stranger.client);

    expect(statuses, contains(ConnectionStatus.error));
    expect(statuses, isNot(contains(ConnectionStatus.connected)));
  });
}
