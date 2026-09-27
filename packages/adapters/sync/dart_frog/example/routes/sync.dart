import 'dart:io';

import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Server–client mode: the server holds the document, validates the changes
/// and takes aligned snapshots.
///
/// Connect with `WebSocketClient` at `ws://localhost:8080/sync`, using
/// [exampleDocumentId] — the handshake is refused for a document the registry
/// does not have.
///
/// The `Authorization` check is here to show the point of doing this in a
/// route: the request is available *before* the socket exists, so a client
/// that fails it gets an ordinary 401 and never reaches the protocol. Replace
/// it with a real check, or drop it.
Future<Response> onRequest(RequestContext context) async {
  final token = context.request.headers[HttpHeaders.authorizationHeader];
  if (token != null && token != 'Bearer example-token') {
    return Response(statusCode: HttpStatus.unauthorized);
  }

  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
