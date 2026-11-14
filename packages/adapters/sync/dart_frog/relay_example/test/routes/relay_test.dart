// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart' hide Handler;
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:crdt_socket_sync_dart_frog_relay_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../../main.dart' as app;
import '../../routes/_middleware.dart' as root;
import '../../routes/relay.dart' as relay;

/// The handler tree `dart_frog dev` builds from `routes/`.
Handler _buildHandler() {
  final router = Router()..all('/relay', relay.onRequest);
  return const Pipeline()
      .addMiddleware(root.middleware)
      .addHandler(router.call);
}

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
  late HttpServer server;
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
    // What `init` in `main.dart` does, without the signal handlers.
    await relayHost.start();

    server = await app.run(_buildHandler(), InternetAddress.loopbackIPv4, 0);
    url = 'ws://127.0.0.1:${server.port}/relay';
  });

  tearDownAll(() async {
    for (final client in clients) {
      await client.disconnect();
      client
        ..dispose()
        ..document.dispose();
    }
    await server.close(force: true);
    await relayHost.dispose();
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
