import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:crdt_socket_sync_dart_frog_relay_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Puts the host in the context, under the type `context.read` matches on.
///
/// The host is built once, at the top level of `host.dart`; this only hands
/// the same instance to every request.
Handler middleware(Handler handler) {
  return handler.use(crdtRelayHostProvider(relayHost));
}
