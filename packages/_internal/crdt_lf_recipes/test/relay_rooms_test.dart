// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_recipes/relay_rooms/client.dart';
import 'package:crdt_lf_recipes/relay_rooms/server.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late WebSocketRelayServer server;
  late String url;
  final clients = <WebSocketRelayClient>[];

  Future<({WebSocketRelayClient client, CRDTFugueTextHandler text})> join(
    String room,
  ) async {
    final peer = await joinRoom(url, room);
    clients.add(peer.client);
    return peer;
  }

  setUp(() async {
    server = await startRelay(port: 0); // port 0: any free port
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

  test('two clients in the same room converge', () async {
    final alice = await join('a');
    final bob = await join('a');

    alice.text.insert(0, 'Hello');
    await waitForText(bob.client.document, bob.text, 'Hello');

    bob.text.insert(5, ', world');
    await waitForText(alice.client.document, alice.text, 'Hello, world');
  });

  test('a client in another room does not see the edits', () async {
    final alice = await join('a');
    final bob = await join('a');
    final carol = await join('b');

    alice.text.insert(0, 'Hello');
    await waitForText(bob.client.document, bob.text, 'Hello');

    expect(carol.text.value, isEmpty);
  });

  test('a client that joins late gets the existing text', () async {
    final alice = await join('a');
    final bob = await join('a');

    alice.text.insert(0, 'Hello');
    // Bob has it, so the relay has stored it.
    await waitForText(bob.client.document, bob.text, 'Hello');

    final carol = await join('a');
    await waitForText(carol.client.document, carol.text, 'Hello');
  });
}
