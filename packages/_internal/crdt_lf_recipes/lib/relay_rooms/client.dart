// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

// #docregion client
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';

/// Opens the text of [room] and joins it on the relay at [url].
Future<({WebSocketRelayClient client, CRDTFugueTextHandler text})> joinRoom(
  String url,
  String room,
) async {
  // The document id is the room: the same id on two clients, the same room.
  final document = CRDTDocument(documentId: room, peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(document, 'body');

  final client = WebSocketRelayClient(
    url: url,
    document: document,
    author: document.peerId,
  );

  // The welcome brings what the room already holds, merged into the document.
  await client.connect();

  return (client: client, text: text);
}
// #enddocregion client

Future<void> main(List<String> args) async {
  final room = args.isEmpty ? 'lobby' : args.first;
  final (:client, :text) = await joinRoom('ws://localhost:8080', room);
  client.document.updates.listen((_) => stdout.writeln(text.value));

  // #docregion edit
  text.insert(text.value.runes.length, 'Hello from ${client.author}\n');
  // #enddocregion edit

  // #docregion close
  await ProcessSignal.sigint.watch().first;
  await client.disconnect();
  client.dispose();
  client.document.dispose();
  // #enddocregion close
}
