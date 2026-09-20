import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync/server.dart';

/// The document the CRDT-aware route serves.
///
/// In this mode the server holds the documents, so it has to be told which
/// ones exist before a client may handshake against one. A real backend would
/// create them from whatever owns that decision.
const exampleDocumentId = 'example-document';

/// The hosts for this process.
///
/// Constructed at the top level, so `_middleware.dart` finds them when Dart
/// Frog builds the handler tree. Construction is synchronous and touches no
/// IO; anything async goes in [ExampleHosts.start], which the `init()` in
/// `main.dart` awaits before the first request can arrive.
///
/// One instance per process, shared by every request: a host per request would
/// give each client its own empty room.
final hosts = ExampleHosts();

/// The two session hosts this example serves.
///
/// Neither owns a socket — Dart Frog upgrades the requests and hands them
/// over. Both stores are in-memory, so a restart loses everything; swap in a
/// `PersistentServerRegistry` (with `crdt_lf_hive`, `crdt_lf_sqlite` or
/// `crdt_lf_drift`) and a durable `RelayStore` for anything real.
class ExampleHosts {
  /// Builds both hosts. Nothing here touches IO — see [start].
  ExampleHosts()
      : this._(
          registry: InMemoryCRDTServerRegistry(),
          relayStore: InMemoryRelayStore(),
        );

  ExampleHosts._({
    required InMemoryCRDTServerRegistry registry,
    required InMemoryRelayStore relayStore,
  })  : _registry = registry,
        sync = DocumentSessionHost(serverRegistry: registry),
        relay = RelaySessionHost(store: relayStore);

  final InMemoryCRDTServerRegistry _registry;

  /// The CRDT-aware host behind `/sync`.
  final DocumentSessionHost sync;

  /// The relay host behind `/relay`.
  final RelaySessionHost relay;

  /// Registers the example document and starts both hosts.
  ///
  /// Safe to call more than once: the document is created only the first
  /// time, and a running host ignores a second `start()`.
  ///
  /// Starting is optional — a host with no transport of its own starts on its
  /// first connection — but doing it here puts the `started` event at a point
  /// we chose, before anyone can connect.
  Future<void> start() async {
    // `addDocument` replaces an existing document with an empty one, which
    // would wipe every change held in memory.
    if (!await _registry.hasDocument(exampleDocumentId)) {
      await _registry.addDocument(exampleDocumentId);
    }
    await sync.start();
    await relay.start();
  }

  /// Sends every server event to [log], so the console shows what the protocol
  /// is doing. A real backend would use its logger.
  void logEvents(void Function(String line) log) {
    sync.serverEvents.listen(
      (e) => log('[sync]  ${e.type.name}: ${e.message}'),
    );
    relay.serverEvents.listen(
      (e) => log('[relay] ${e.type.name}: ${e.message}'),
    );
  }

  /// Closes the open sessions and the registry under the sync host.
  ///
  /// With a durable registry this is where pending writes are flushed, so a
  /// backend that skips it loses data on shutdown. A `RelayStore` has no
  /// close; a durable one must be closed here by the backend.
  Future<void> dispose() async {
    await sync.dispose();
    await relay.dispose();
  }
}
