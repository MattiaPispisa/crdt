// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:serverpod/serverpod.dart' show Serverpod;
import 'package:test/test.dart';

import '../bin/main.dart' as app;

/// Waits until [text] reads [expected].
Future<void> _waitForText(
  CRDTDocument document,
  CRDTFugueTextHandler text,
  String expected,
) async {
  if (text.value == expected) {
    return;
  }
  await document.updates
      .firstWhere((_) => text.value == expected)
      .timeout(const Duration(seconds: 5));
}

void main() {
  late Serverpod pod;
  late String url;
  final clients = <WebSocketRelayClient>[];

  Future<({WebSocketRelayClient client, CRDTFugueTextHandler text})> join(
    String room,
  ) async {
    final document = CRDTDocument(documentId: room, peerId: PeerId.generate());
    final text = CRDTFugueTextHandler(document, 'body');
    final client = WebSocketRelayClient(
      url: url,
      document: document,
      author: document.peerId,
    );
    clients.add(client);
    expect(await client.connect(), isTrue);
    return (client: client, text: text);
  }

  setUpAll(() async {
    // Port 0: any free port.
    pod = await app.startServer([], webPort: 0, apiPort: 0);
    url = 'ws://127.0.0.1:${pod.webServer.port}/relay';
  });

  tearDownAll(() async {
    for (final client in clients) {
      await client.disconnect();
      client
        ..dispose()
        ..document.dispose();
    }
    // Runs the shutdown task, which disposes the host.
    await pod.shutdown(exitProcess: false);
  });

  test('an edit on one client reaches the other through /relay', () async {
    final alice = await join('room');
    final bob = await join('room');

    alice.text.insert(0, 'Hello');
    await _waitForText(bob.client.document, bob.text, 'Hello');

    bob.text.insert(5, ', world');
    await _waitForText(alice.client.document, alice.text, 'Hello, world');
  });
}
