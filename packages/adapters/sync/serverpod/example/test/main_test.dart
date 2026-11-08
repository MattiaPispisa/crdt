// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_serverpod_example/src/host.dart';
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
  late Directory dbDir;
  late Serverpod pod;
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
    dbDir = await Directory.systemTemp.createTemp('serverpod_example_');
    final example = await ExampleHost.open(dbPath: dbDir.path);
    // Port 0: any free port.
    pod = await app.startServer([], example, webPort: 0, apiPort: 0);
    url = 'ws://127.0.0.1:${pod.webServer.port}/sync';
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

  test('a wrong token gets a 401 before the upgrade', () async {
    final http = HttpClient();
    addTearDown(http.close);

    final request = await http.getUrl(
      Uri.parse('http://127.0.0.1:${pod.webServer.port}/sync'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer wrong');
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}
