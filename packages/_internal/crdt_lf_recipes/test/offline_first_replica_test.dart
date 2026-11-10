// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/offline_first_replica/note_page.dart';
import 'package:crdt_lf_recipes/offline_first_replica/open_note.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// A widget test replaces the HTTP client of the process with a mock: the
// page test puts the real one back for its sockets.

/// Waits until [done] holds.
Future<void> eventually(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

/// The text of the note in [replica].
String textOf(CRDTReplica replica) {
  return replica.document.handler(CRDTFugueTextHandler.spec, 'note').value;
}

void main() {
  late Directory directory;
  late WebSocketRelayServer server;
  late String url;

  /// A second device: its own document, in memory, on the same room.
  Future<CRDTReplica> openPeer() async {
    final replica = await CRDTReplica.open(
      documentId: 'note',
      sync:
          (document) => WebSocketRelayClient(
            url: url,
            document: document,
            author: document.peerId,
          ),
    );
    CRDTFugueTextHandler(replica.document, 'note');
    return replica;
  }

  setUpAll(CRDTHive.initialize);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('offline_first_replica');
    Hive.init(directory.path);
    server = WebSocketRelayServer(
      serverFactory: () => HttpServer.bind('localhost', 0),
    );
    await server.start();
    url = 'ws://localhost:${server.port}';
  });

  tearDown(() async {
    await server.dispose();
    await CRDTHive.closeAllBoxes();
    directory.deleteSync(recursive: true);
  });

  test('an edit on one device reaches the other', () async {
    final phone = await openNote(url);
    final laptop = await openPeer();

    phone.document
        .handler(CRDTFugueTextHandler.spec, 'note')
        .insert(0, 'Hello');
    await eventually(() => textOf(laptop) == 'Hello');

    await laptop.close();
    await phone.close();
  });

  test('an edit made offline is kept, and sent after a restart', () async {
    final onlineUrl = url;
    // Nothing listens on this port.
    final dead = await HttpServer.bind('localhost', 0);
    url = 'ws://localhost:${dead.port}';
    await dead.close();

    final offline = await openNote(url);
    expect(offline.client!.connectionStatusValue.isConnected, isFalse);
    offline.document
        .handler(CRDTFugueTextHandler.spec, 'note')
        .insert(0, 'Written offline');
    await offline.close();

    url = onlineUrl;
    final laptop = await openPeer();
    final online = await openNote(url);
    expect(textOf(online), 'Written offline');
    await eventually(() => textOf(laptop) == 'Written offline');

    await laptop.close();
    await online.close();
  });
  testWidgets('the page edits the note and shows the connection', (
    tester,
  ) async {
    HttpOverrides.global = null;

    /// Pumps until [done] holds, letting the sockets and Hive run in between.
    Future<void> pumpUntil(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        // Fake time too, for the timers of the client.
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(done(), isTrue);
    }

    final laptop = (await tester.runAsync(openPeer))!;
    await tester.pumpWidget(MaterialApp(home: NotePage(url: url)));
    await pumpUntil(() => find.text('Online').evaluate().isNotEmpty);

    await tester.enterText(find.byType(TextField), 'Hello');
    await pumpUntil(() => textOf(laptop) == 'Hello');

    await tester.runAsync(server.stop);
    await pumpUntil(() => find.text('Online').evaluate().isEmpty);
    expect(find.byType(TextField), findsOneWidget);

    // The page closes the replica: give the close, and the timers of the
    // client, the time to end.
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    // The boxes the page opened in the test zone close here, while it is
    // still pumped.
    await tester.runAsync(laptop.close);
    var closed = false;
    unawaited(CRDTHive.closeAllBoxes().then((_) => closed = true));
    await pumpUntil(() => closed);
  });
}
