// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart' hide Handler;
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../../main.dart' as app;
import '../../routes/_middleware.dart' as root;
import '../../routes/sync.dart' as sync;

/// The handler tree `dart_frog dev` builds from `routes/`.
Handler _buildHandler() {
  final router = Router()..all('/sync', sync.onRequest);
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
  late Directory dbDir;
  late HttpServer server;
  late String url;
  final clients = <WebSocketClient>[];

  Future<({WebSocketClient client, CRDTFugueTextHandler text})>
      connect() async {
    final document = CRDTDocument(
      documentId: exampleDocumentId,
      peerId: PeerId.generate(),
    );
    final text = CRDTFugueTextHandler(document, 'body');
    final client = WebSocketClient(
      url: url,
      document: document,
      author: document.peerId,
    );
    clients.add(client);
    expect(await client.connect(), isTrue);
    return (client: client, text: text);
  }

  setUpAll(() async {
    dbDir = await Directory.systemTemp.createTemp('dart_frog_example_');
    // What `init` in `main.dart` does, without the signal handlers.
    example = await ExampleHost.open(dbPath: dbDir.path);
    await example.host.start();

    server = await app.run(_buildHandler(), InternetAddress.loopbackIPv4, 0);
    url = 'ws://127.0.0.1:${server.port}/sync?token=${sync.exampleToken}';
  });

  tearDownAll(() async {
    for (final client in clients) {
      await client.disconnect();
      client
        ..dispose()
        ..document.dispose();
    }
    await server.close(force: true);
    await example.dispose();
    await dbDir.delete(recursive: true);
  });

  test('an edit on one client reaches the other through /sync', () async {
    final alice = await connect();
    final bob = await connect();

    alice.text.insert(0, 'Hello');
    await _waitForText(bob.client.document, bob.text, 'Hello');

    bob.text.insert(5, ', world');
    await _waitForText(alice.client.document, alice.text, 'Hello, world');
  });

  for (final (name, query) in [
    ('no token', ''),
    ('a wrong token', '?token=wrong'),
  ]) {
    test('$name gets a 401 before the upgrade', () async {
      final http = HttpClient();
      addTearDown(http.close);

      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/sync$query'),
      );
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  }
}
