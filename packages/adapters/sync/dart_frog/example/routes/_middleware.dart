import 'package:crdt_socket_sync_dart_frog/crdt_socket_sync_dart_frog.dart';
import 'package:crdt_socket_sync_dart_frog_example/src/hosts.dart';
import 'package:dart_frog/dart_frog.dart';

/// Puts both hosts in the context, under the types `context.read` matches on.
///
/// The hosts are built once, at the top level of `hosts.dart`; this only
/// hands the same two instances to every request.
Handler middleware(Handler handler) {
  return handler
      .use(crdtSyncHostProvider(hosts.sync))
      .use(crdtRelayHostProvider(hosts.relay));
}
