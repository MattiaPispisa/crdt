import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:greyhound_markdown_server_dart_frog/src/host.dart';

/// Gives every request the same [relayHost].
Handler middleware(Handler handler) {
  return handler.use(crdtRelayHostProvider(relayHost));
}
