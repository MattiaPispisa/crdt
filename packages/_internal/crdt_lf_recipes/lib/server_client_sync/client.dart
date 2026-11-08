// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

// #docregion client
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';

/// Opens the note [documentId] and connects it to the server at [url].
///
/// [onStatus] gets every move of the connection status.
Future<({WebSocketClient client, CRDTFugueTextHandler text})> connectClient(
  String url, {
  String documentId = 'notes',
  void Function(ConnectionStatus status)? onStatus,
}) async {
  // The same documentId on every client: the server registered it.
  final document = CRDTDocument(
    documentId: documentId,
    peerId: PeerId.generate(),
  );
  final text = CRDTFugueTextHandler(document, 'body');

  final client = WebSocketClient(
    url: url,
    document: document,
    author: document.peerId,
  );
  client.connectionStatus.listen(onStatus);

  // Returns false when the handshake fails (DOCUMENT_NOT_FOUND, say),
  // and the client retries on its own.
  await client.connect();

  return (client: client, text: text);
}
// #enddocregion client

// #docregion status
/// A short description of [status], for a log or a status bar.
String describe(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.connecting => 'Connecting…',
    ConnectionStatus.connected => 'Online',
    ConnectionStatus.reconnecting => 'Connection lost, retrying…',
    ConnectionStatus.disconnected => 'Offline',
    ConnectionStatus.error => 'Connection error',
    // Terminal: the server refused this build. Ask the user to update.
    ConnectionStatus.unsupported => 'Update required',
  };
}
// #enddocregion status

Future<void> main(List<String> args) async {
  final (:client, :text) = await connectClient(
    'ws://localhost:8080',
    onStatus: (status) => stdout.writeln(describe(status)),
  );
  client.document.updates.listen((_) => stdout.writeln(text.value));

  // #docregion edit
  // A local edit: the client sends it to the server on its own.
  text.insert(
    text.value.runes.length,
    '${args.isEmpty ? 'Hello' : args.join(' ')}\n',
  );
  // #enddocregion edit

  // #docregion close
  await ProcessSignal.sigint.watch().first;
  await client.disconnect();
  client.dispose();
  client.document.dispose();
  // #enddocregion close
}
