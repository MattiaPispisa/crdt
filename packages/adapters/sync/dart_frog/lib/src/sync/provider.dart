import 'package:crdt_socket_sync/server.dart';
import 'package:dart_frog/dart_frog.dart';

/// [Middleware] that gives the routes below it [host].
///
/// ```dart
/// // routes/_middleware.dart
/// Handler middleware(Handler handler) {
///   return handler.use(crdtSyncHostProvider(host));
/// }
/// ```
///
/// A plain `provider<DocumentSessionHost>((_) => host)` does the same thing.
/// This exists because the type argument is what `context.read` matches on,
/// and getting it wrong — passing a `WebSocketServer`, say — compiles and then
/// throws at request time with a message about a provider that was never set
/// up.
///
/// Give each host its own plugin instances: a `ServerSyncPlugin` binds to one
/// host, and a second binding throws.
Middleware crdtSyncHostProvider(DocumentSessionHost host) {
  return provider<DocumentSessionHost>((_) => host);
}
