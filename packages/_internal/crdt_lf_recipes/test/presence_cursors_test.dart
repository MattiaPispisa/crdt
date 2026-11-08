// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_recipes/presence_cursors/presence.dart';
import 'package:crdt_lf_recipes/presence_cursors/server.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain tests, no testWidgets: a widget test replaces the HTTP client of the
// process with a mock, and the real sockets below need the real one.

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

void main() {
  late WebSocketRelayServer server;
  late String url;
  final notes = <SharedNote>[];

  Future<SharedNote> join(String name, Color color) async {
    final note = await joinNote(url, name: name, color: color);
    notes.add(note);
    return note;
  }

  setUp(() async {
    server = await startPresenceRelay(port: 0); // port 0: any free port
    url = 'ws://localhost:${server.port}';
  });

  tearDown(() async {
    for (final note in notes) {
      await note.client.disconnect();
      note.client.dispose();
      note.client.document.dispose();
    }
    notes.clear();
    await server.dispose();
  });

  test('a caret reaches the other peer, with the name and color', () async {
    const red = Color(0xFFF44336);
    final alice = await join('Alice', red);
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
        id: alice.client.sessionId!,
        color: red,
        label: 'Alice',
        base: caret,
      ),
    ]);
    // Alice sees Bob, but Bob has no caret to draw.
    expect(remoteCursors(alice.presence, alice.presence.awareness), isEmpty);
  });

  test('a withdrawn caret and a peer that leaves are gone', () async {
    final alice = await join('Alice', const Color(0xFFF44336));
    final bob = await join('Bob', const Color(0xFF2196F3));
    final aliceId = alice.client.sessionId!;

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

    // The relay drops the state of a peer that disconnects.
    await alice.client.disconnect();
    await waitForPresence(
      bob,
      (awareness) => !awareness.states.containsKey(aliceId),
    );
  });
}
