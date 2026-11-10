// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion route
import 'dart:io';

import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// The token a client sends. Replace it with a real check.
const exampleToken = 'example-token';

/// Server–client mode: the server holds the document, validates the changes
/// and takes aligned snapshots.
///
/// Connect with `WebSocketClient` at
/// `ws://localhost:8080/sync?token=example-token`, using [exampleDocumentId]:
/// the handshake is refused for a document the registry does not have.
///
/// The token travels in the query: `WebSocketClient` sends no headers, and a
/// browser cannot set them on a WebSocket. A caller without the token gets an
/// ordinary 401 and never reaches the protocol.
Future<Response> onRequest(RequestContext context) async {
  final token = context.request.uri.queryParameters['token'];
  if (token != exampleToken) {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
// #enddocregion route
