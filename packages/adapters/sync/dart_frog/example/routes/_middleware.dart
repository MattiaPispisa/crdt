import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Puts the host in the context, under the type `context.read` matches on.
///
/// The host is opened once by `init()` in `main.dart`; this only hands the
/// same instance to every request.
Handler middleware(Handler handler) {
  return handler.use(crdtSyncHostProvider(example.host));
}
