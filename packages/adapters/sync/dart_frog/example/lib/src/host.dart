import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/server.dart';
import 'package:hive/hive.dart';

/// The document the route serves.
///
/// In this mode the server holds the documents, so it has to be told which
/// ones exist before a client may handshake against one. A real backend would
/// create them from whatever owns that decision.
const exampleDocumentId = 'example-document';

/// Snapshot a document once its log passes this many changes.
const _compactAfter = 20;

/// The host for this process.
///
/// Set by `init()` in `main.dart`, which Dart Frog awaits before it builds the
/// handler tree — so `_middleware.dart` finds it ready. One instance per
/// process, shared by every request: a host per request would give each
/// client its own empty document.
late final ExampleHost example;

/// A [DocumentSessionHost] whose documents live in Hive.
///
/// The host has no socket of its own — Dart Frog upgrades the requests and
/// hands them over. [PersistentServerRegistry] does the storing; this class
/// only says where (a Hive database in a directory) and owns the lifecycle.
class ExampleHost {
  ExampleHost._({
    required CRDTHiveBackend backend,
    required PersistentServerRegistry registry,
  })  : _backend = backend,
        host = DocumentSessionHost(serverRegistry: registry);

  /// Opens the Hive database in [dbPath] and makes sure [exampleDocumentId]
  /// exists. The host is left for the caller to start, so it can subscribe to
  /// [DocumentSessionHost.serverEvents] first.
  ///
  /// A second call with the same [dbPath] finds the document and its history
  /// again: that is the persistence.
  static Future<ExampleHost> open({required String dbPath}) async {
    Hive.init(dbPath);
    _registerAdapters();

    final backend = await CRDTHive.open();
    final registry = PersistentServerRegistry(
      backend: backend,
      compactAfter: _compactAfter,
    );
    if (!await registry.hasDocument(exampleDocumentId)) {
      await registry.addDocument(exampleDocumentId);
    }

    return ExampleHost._(backend: backend, registry: registry);
  }

  static bool _adaptersRegistered = false;

  // Hive throws on a type id registered twice, and `open` runs more than once
  // in the tests.
  static void _registerAdapters() {
    if (_adaptersRegistered) {
      return;
    }
    CRDTHive.initialize();
    _adaptersRegistered = true;
  }

  final CRDTHiveBackend _backend;

  /// The CRDT-aware host behind `/sync`.
  final DocumentSessionHost host;

  /// Sends every server event to [log], so the console shows what the
  /// protocol is doing. A real backend would use its logger.
  void logEvents(void Function(String line) log) {
    host.serverEvents.listen((e) => log('[sync] ${e.type.name}: ${e.message}'));
  }

  /// Closes the open sessions, then the registry and the database under it.
  ///
  /// The registry is closed by [DocumentSessionHost.dispose]: that is where
  /// the writes still waiting are flushed, so a backend that skips this loses
  /// data on shutdown. Every Hive box is closed after it — the backend closes
  /// only its own, and the box the identities share stays open otherwise.
  Future<void> dispose() async {
    await host.dispose();
    await _backend.close();
    await CRDTHive.closeAllBoxes();
  }
}
