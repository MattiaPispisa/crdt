import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';

/// Upgrades `GET /room/<id>` and hands the socket to the relay host.
///
/// [id] is unused: the host takes the room from the client's hello frame,
/// which carries the same id.
Future<Response> onRequest(RequestContext context, String id) async {
  return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(context);
}
