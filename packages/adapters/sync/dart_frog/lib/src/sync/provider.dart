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
Middleware crdtSyncHostProvider(DocumentSessionHost host) {
  return provider<DocumentSessionHost>((_) => host);
}
