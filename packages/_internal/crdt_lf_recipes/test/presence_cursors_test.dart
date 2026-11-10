// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/presence_cursors/note_page.dart';
import 'package:crdt_lf_recipes/presence_cursors/presence.dart';
import 'package:crdt_lf_recipes/presence_cursors/server.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// A widget test replaces the HTTP client of the process with a mock: the
// page test puts the real one back for its sockets.

/// Waits until [done] holds for the presence of [note].
Future<void> waitForPresence(
  SharedNote note,
  bool Function(DocumentAwareness awareness) done,
) async {
  if (done(note.presence.awareness)) return;
  await note.presence.awarenessStream
      .firstWhere(done)
      .timeout(const Duration(seconds: 5));
}

/// Waits until the client of [note] is connected.
Future<void> waitForConnection(SharedNote note) async {
  final client = note.replica.client!;
  if (client.connectionStatusValue.isConnected) return;
  await client.connectionStatus
      .firstWhere((status) => status.isConnected)
      .timeout(const Duration(seconds: 5));
}

void main() {
  late Directory directory;
  late WebSocketRelayServer server;
  late String url;
  final notes = <SharedNote>[];

  /// The recipe's note, stored in Hive: one per test, as on one device.
  Future<SharedNote> open(String name, Color color) async {
    final note = await openNote(url, name: name, color: color);
    notes.add(note);
    await waitForConnection(note);
    return note;
  }

  /// Another device: the same note and presence, in memory.
  Future<SharedNote> join(String name, Color color) async {
    final presence = ClientAwarenessPlugin(
      initialMetadata: {'name': name, 'color': color.toARGB32()},
    );
    final replica = await CRDTReplica.open(
      documentId: 'note',
      sync:
          (document) => WebSocketRelayClient(
            url: url,
            document: document,
            author: document.peerId,
            plugins: [presence],
          ),
    );
    final text = CRDTFugueTextHandler(replica.document, 'note');
    final note = (replica: replica, presence: presence, text: text);
    notes.add(note);
    await waitForConnection(note);
    return note;
  }

  setUpAll(CRDTHive.initialize);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('presence_cursors');
    Hive.init(directory.path);
    server = await startPresenceRelay(port: 0); // port 0: any free port
    url = 'ws://localhost:${server.port}';
  });

  tearDown(() async {
    for (final note in notes) {
      await note.replica.close();
    }
    notes.clear();
    await server.dispose();
    await CRDTHive.closeAllBoxes();
    directory.deleteSync(recursive: true);
  });

  test('a caret reaches the other peer, with the name and color', () async {
    const red = Color(0xFFF44336);
    final alice = await open('Alice', red);
    final bob = await join('Bob', const Color(0xFF2196F3));

    alice.text.insert(0, 'Hello');
    final caret = alice.text.stablePositionAt(5);
    publishCaret(alice.presence, caret, caret);

    await waitForPresence(
      bob,
      (awareness) => remoteCursors(bob.presence, awareness).isNotEmpty,
    );
    final cursors = remoteCursors(bob.presence, bob.presence.awareness);
    expect(cursors, [
      CrdtTextCursor(
        id: alice.replica.client!.sessionId!,
        color: red,
        label: 'Alice',
        base: caret,
      ),
    ]);
    // Alice sees Bob, but Bob has no caret to draw.
    expect(remoteCursors(alice.presence, alice.presence.awareness), isEmpty);
  });

  test('a withdrawn caret and a peer that leaves are gone', () async {
    final alice = await open('Alice', const Color(0xFFF44336));
    final bob = await join('Bob', const Color(0xFF2196F3));
    final aliceId = alice.replica.client!.sessionId!;

    final start = alice.text.stablePositionAt(0);
    publishCaret(alice.presence, start, null);
    await waitForPresence(
      bob,
      (awareness) => remoteCursors(bob.presence, awareness).isNotEmpty,
    );

    // What the field reports when it loses focus.
    publishCaret(alice.presence, null, null);
    await waitForPresence(
      bob,
      (awareness) => remoteCursors(bob.presence, awareness).isEmpty,
    );
    expect(bob.presence.awareness.states[aliceId]?.metadata['name'], 'Alice');

    // The relay drops the state of a peer that leaves.
    await alice.replica.close();
    await waitForPresence(
      bob,
      (awareness) => !awareness.states.containsKey(aliceId),
    );
  });

  testWidgets('the page publishes its caret and draws the other one', (
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

    final bob =
        (await tester.runAsync(() => join('Bob', const Color(0xFF2196F3))))!;
    await tester.pumpWidget(
      MaterialApp(
        home: NotePage(url: url, name: 'Alice', color: const Color(0xFFF44336)),
      ),
    );
    await pumpUntil(() => find.byType(TextField).evaluate().isNotEmpty);

    bob.text.insert(0, 'Hello');
    final caret = bob.text.stablePositionAt(5);
    publishCaret(bob.presence, caret, caret);
    List<CrdtTextCursor> drawn() =>
        tester
            .widget<CrdtTextCursorsOverlay>(find.byType(CrdtTextCursorsOverlay))
            .cursors;
    await pumpUntil(() => drawn().length == 1);
    expect(drawn().single.label, 'Bob');

    // Focus gives the field a selection: the page publishes it.
    await tester.tap(find.byType(TextField));
    await pumpUntil(
      () => remoteCursors(bob.presence, bob.presence.awareness).isNotEmpty,
    );
    expect(
      remoteCursors(bob.presence, bob.presence.awareness).single.label,
      'Alice',
    );

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
    var closed = false;
    unawaited(CRDTHive.closeAllBoxes().then((_) => closed = true));
    await pumpUntil(() => closed);
  });
}
