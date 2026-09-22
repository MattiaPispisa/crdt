import 'package:crdt_socket_sync/relay_server.dart';
import 'package:dart_frog/dart_frog.dart';

/// [Middleware] that gives the routes below it the relay [host].
///
/// ```dart
/// // routes/_middleware.dart
/// Handler middleware(Handler handler) {
///   return handler.use(crdtRelayHostProvider(host));
/// }
/// ```
///
/// A plain `provider<RelaySessionHost>((_) => host)` does the same thing;
/// this pins the type argument `context.read` matches on, so a wrong host
/// type fails at compile time rather than at request time.
///
/// Give each host its own plugin instances: a `ServerSyncPlugin` binds to one
/// host, and a second binding throws.
Middleware crdtRelayHostProvider(RelaySessionHost host) {
  return provider<RelaySessionHost>((_) => host);
}
