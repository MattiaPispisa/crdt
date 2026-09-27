import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';

/// Relay mode: the server rebroadcasts opaque CRDT blobs to the other clients
/// of a room and persists them, without ever reading them.
///
/// Connect with `WebSocketRelayClient` at `ws://localhost:8080/relay`. The
/// room is the document id inside the hello frame, not part of this path.
Future<Response> onRequest(RequestContext context) async {
  return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(context);
}
