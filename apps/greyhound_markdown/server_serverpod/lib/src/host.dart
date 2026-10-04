import 'package:crdt_socket_sync/relay_server.dart';

/// The relay host behind `/room/<id>`, one per process.
///
/// It runs the awareness plugin, because the client shares cursors through
/// it. Rooms live in memory, so a restart empties them.
final relayHost = RelaySessionHost(
  store: InMemoryRelayStore(),
  plugins: [ServerAwarenessPlugin()],
);

/// Sends every server event of [relayHost] to [log].
void logRelayEvents(void Function(String line) log) {
  relayHost.serverEvents.listen(
    (e) => log('[relay] ${e.type.name}: ${e.message}'),
  );
}
