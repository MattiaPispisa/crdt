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
Middleware crdtRelayHostProvider(RelaySessionHost host) {
  return provider<RelaySessionHost>((_) => host);
}
