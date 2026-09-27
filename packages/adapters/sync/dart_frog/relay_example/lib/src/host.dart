import 'package:crdt_socket_sync/relay_server.dart';

/// The relay host for this process.
///
/// Constructed at the top level, so `_middleware.dart` finds it when Dart Frog
/// builds the handler tree; started by `init()` in `main.dart`. One instance
/// per process, shared by every request: a host per request would give each
/// client its own empty room.
///
/// The host has no socket of its own — Dart Frog upgrades the requests and
/// hands them over. The store is in-memory, so a restart loses every room;
/// there is no durable `RelayStore` in this repository yet, so a real backend
/// implements one over its database and closes it after `dispose()`.
final relayHost = RelaySessionHost(store: InMemoryRelayStore());

/// Sends every server event to [log], so the console shows what the protocol
/// is doing. A real backend would use its logger.
void logRelayEvents(void Function(String line) log) {
  relayHost.serverEvents.listen(
    (e) => log('[relay] ${e.type.name}: ${e.message}'),
  );
}
