import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:en_logger/en_logger.dart';

const _kDocumentsBox = 'documents';
const _kDefaultSnapshotInterval = Duration(minutes: 30);
const _kDefaultMinChangesForSnapshot = 20;

/// A server-side CRDT document registry that uses Hive for persistence.
///
/// This implementation is designed for efficiency and scalability by lazy-loading
/// documents from storage. On initialization, it only loads the list of document
/// IDs, and the full document state (snapshot and changes) is only fetched from
/// Hive upon the first request for that specific document.
///
/// It also periodically creates snapshots for loaded documents to compact change
/// history and improve performance.
///
/// Key features:
/// - **Lazy Loading**: Documents are not loaded into memory until they are needed.
/// - **Periodic Snapshotting**: Automatically creates snapshots for active
///   documents at a configurable interval (defaults to 5 minutes).
/// - **Hive-based Persistence**: All changes and snapshots are stored in Hive
///   boxes, ensuring data durability.
/// - **Efficient Writes**: Changes are appended to storage without requiring a
///   full document reload.
/// - **Resource Management**: Provides methods to properly close Hive boxes and
///   clean up resources.
class HiveServerRegistry extends CRDTServerRegistry {
  final Map<String, _CrdtDocumentRegistryItem> _documents;
  final Duration _snapshotInterval;
  final int _minChangesForSnapshot;
  final EnLogger _logger;
  Timer? _snapshotTimer;
  late WebSocketServer _server;

  HiveServerRegistry._(
    this._documents,
    this._snapshotInterval,
    this._minChangesForSnapshot,
    this._logger,
  );

  /// Initializes the registry by loading all document IDs from a dedicated Hive box.
  ///
  /// This method prepares the registry for use but does not load any document
  /// content, making the startup process fast and lightweight.
  ///
  /// It also starts a periodic timer to create snapshots for loaded documents.
  static Future<HiveServerRegistry> init({
    Duration snapshotInterval = _kDefaultSnapshotInterval,
    int minChangesForSnapshot = _kDefaultMinChangesForSnapshot,
    required EnLogger logger,
  }) async {
    logger.info('Initializing HiveServerRegistry...');

    CRDTHive.initialize();
    final documents = <String, _CrdtDocumentRegistryItem>{};

    final documentIdsBox = await Hive.openBox<String>(_kDocumentsBox);
    logger.info('Found ${documentIdsBox.length} documents in persistence.');
    for (final documentId in documentIdsBox.values) {
      documents[documentId] = _CrdtDocumentRegistryItem.lazy(
        documentId: documentId,
        document: CRDTDocument(peerId: PeerId.parse(documentId)),
      );
    }

    return HiveServerRegistry._(
      documents,
      snapshotInterval,
      minChangesForSnapshot,
      logger,
    ).._startSnapshotTimer();
  }

  void setServer(WebSocketServer server) {
    _server = server;
  }

  /// Starts the periodic timer for creating snapshots.
  void _startSnapshotTimer() {
    _logger.info(
      'Starting periodic snapshot timer with interval $_snapshotInterval.',
    );
    _snapshotTimer = Timer.periodic(_snapshotInterval, (_) {
      _createPeriodicSnapshots();
    });
  }

  /// Iterates through all loaded documents and creates a new snapshot for each.
  ///
  /// This helps to keep the change history small and efficient.
  Future<void> _createPeriodicSnapshots() async {
    _logger.info('Running periodic snapshot creation...');
    // Iterate over a copy of the keys to prevent concurrent modification errors
    for (final documentId in _documents.keys.toList()) {
      final item = _documents[documentId];
      if (item != null && item.loaded) {
        try {
          final changesCount = item.storage!.changes.box.length;
          if (changesCount > _minChangesForSnapshot) {
            _logger.info(
              'Creating snapshot for document $documentId ($changesCount changes)...',
            );
            final snapshot = await createSnapshot(documentId);
            final changes = item.document.exportChanges();
            await _server.broadcastMessage(
              Message.documentStatus(
                documentId: documentId,
                snapshot: snapshot,
                changes: changes,
                versionVector: item.document.getVersionVector(),
              ),
            );
          } else {
            _logger.info(
              'Skipping snapshot for $documentId: only $changesCount changes (threshold: $_minChangesForSnapshot)',
            );
          }
        } catch (e, st) {
          _logger.error(
            'Error creating snapshot for document $documentId.\n$e\n$st',
          );
        }
      }
    }
  }

  /// Retrieves the `CRDTDocumentStorage` for a given document, opening it if it
  /// hasn't been accessed yet.
  ///
  /// This is a key part of the lazy-loading mechanism, ensuring that Hive boxes
  /// are only opened when necessary.
  Future<CRDTDocumentStorage> _getStorage(String documentId) async {
    final item = _documents[documentId]!;
    if (item.storage == null) {
      _logger.info('Opening storage for document $documentId...');
      item.storage = await CRDTHive.openStorageForDocument(documentId);
    }
    return item.storage!;
  }

  /// Loads a document's full state (snapshot and changes) from Hive into the
  /// in-memory `CRDTDocument` instance.
  ///
  /// This operation is performed only once per document, the first time it's
  /// accessed. Subsequent calls for the same document do nothing.
  Future<void> _loadDocument(String documentId) async {
    final item = _documents[documentId];
    if (item == null || item.loaded) {
      return;
    }

    _logger.info('Lazy-loading document $documentId from persistence...');
    final storage = await _getStorage(documentId);
    final snapshot = storage.snapshots.getSnapshots().lastOrNull;
    final changes = storage.changes.getChanges();

    item.document.import(snapshot: snapshot, changes: changes);
    item.loaded = true;
    _logger.info('Document $documentId loaded successfully.');
  }

  /// Adds a new document to the registry.
  ///
  /// This creates an entry in the document list and prepares it for future use,
  /// but does not yet create any storage boxes.
  @override
  Future<void> addDocument(String documentId, {PeerId? author}) async {
    if (_documents.containsKey(documentId)) {
      return;
    }

    _logger.info('Adding new document: $documentId');
    final documentIdsBox = await Hive.openBox<String>(_kDocumentsBox);
    await documentIdsBox.put(documentId, documentId);

    _documents[documentId] = _CrdtDocumentRegistryItem.lazy(
      documentId: documentId,
      document: CRDTDocument(
        documentId: documentId,
        peerId: author ?? PeerId.generate(),
      ),
    );
  }

  /// Applies a `Change` to a specific document.
  ///
  /// It ensures the document is loaded into memory, applies the change, and then
  /// persists the new change to Hive.
  @override
  Future<bool> applyChange(String documentId, Change change) async {
    final item = _documents[documentId];
    if (item == null) {
      _logger.error(
        'Attempted to apply change to non-existent document: $documentId',
      );
      return false;
    }

    await _loadDocument(documentId);
    final storage = await _getStorage(documentId);
    item.document.applyChange(change);
    await storage.changes.saveChanges([change]);
    return true;
  }

  /// Creates and persists a snapshot of the document's current state.
  ///
  /// This is useful for compacting the change history and improving performance.
  @override
  Future<Snapshot> createSnapshot(String documentId) async {
    final item = _documents[documentId];
    if (item == null) {
      _logger.error(
        'Attempted to create snapshot for non-existent document: $documentId',
      );
      throw Exception('Document not found');
    }

    await _loadDocument(documentId);
    final storage = await _getStorage(documentId);
    final snapshot = item.document.takeSnapshot();

    _logger.info(
      'Saving snapshot for document $documentId, data: ${snapshot.data}',
    );

    await storage.snapshots.saveSnapshot(snapshot);

    await storage.changes.clear().then((_) {
      return storage.changes.saveChanges(item.document.exportChanges());
    });

    return snapshot;
  }

  /// Returns the total number of documents managed by the registry.
  @override
  Future<int> get documentCount async => _documents.length;

  /// Returns a set of all document IDs managed by the registry.
  @override
  Future<Set<String>> get documentIds async => _documents.keys.toSet();

  /// Retrieves a `CRDTDocument` instance by its ID.
  ///
  /// If the document is not already in memory, it will be lazy-loaded from Hive.
  @override
  Future<CRDTDocument?> getDocument(String documentId) async {
    final item = _documents[documentId];
    if (item == null) return null;
    await _loadDocument(documentId);
    return item.document;
  }

  /// Retrieves the latest available `Snapshot` for a document directly from Hive.
  @override
  Future<Snapshot?> getLatestSnapshot(String documentId) async {
    final item = _documents[documentId];
    if (item == null) return null;
    final storage = await _getStorage(documentId);
    return storage.snapshots.getSnapshots().lastOrNull;
  }

  /// Checks if a document with the given ID exists in the registry.
  @override
  Future<bool> hasDocument(String documentId) async =>
      _documents.containsKey(documentId);

  /// Removes a document and all its associated data from both the registry and
  /// Hive storage.
  ///
  /// It also ensures that any open Hive boxes for that document are closed.
  @override
  Future<void> removeDocument(String documentId) async {
    _logger.info('Removing document: $documentId');
    final item = _documents.remove(documentId);
    if (item?.storage != null) {
      await item!.storage!.changes.box.close();
      await item.storage!.snapshots.box.close();
    }

    final documentIdsBox = await Hive.openBox<String>(_kDocumentsBox);
    await documentIdsBox.delete(documentId);
    await CRDTHive.deleteDocumentData(documentId);
  }

  /// Closes all open Hive boxes and cancels the snapshot timer.
  ///
  /// This should be called during application shutdown to ensure a clean exit.
  Future<void> close() async {
    _logger.info('Closing HiveServerRegistry...');
    _snapshotTimer?.cancel();
    for (final item in _documents.values) {
      if (item.storage == null) continue;
      await item.storage!.changes.box.close();
      await item.storage!.snapshots.box.close();
    }
    await Hive.box<String>(_kDocumentsBox).close();
    _logger.info('HiveServerRegistry closed.');
  }

  /// Shows the persistence state of the documents.
  Future<void> showPersistence() async {
    _logger.info('Showing persistence state...');
    for (final documentId in _documents.keys.toList()) {
      await _loadDocument(documentId);
      final item = _documents[documentId]!;
      final storage = item.storage!;

      final changesCount = storage.changes.box.length;
      final snapshots = storage.snapshots.getSnapshots();
      final latestSnapshot = snapshots.lastOrNull;

      _logger.info('Document: $documentId');
      _logger.info('  Changes: $changesCount');
      _logger.info('  Snapshots: ${snapshots.length}');
      if (latestSnapshot != null) {
        _logger.info('  Latest snapshot:');
        _logger.info('    VV: ${latestSnapshot.versionVector}');
        _logger.info('    Data: ${latestSnapshot.data}');
      }
    }
  }
}

/// A private wrapper class that holds the in-memory state for a registered document.
///
/// It contains the `CRDTDocument` instance, a nullable reference to its
/// `CRDTDocumentStorage`, and a `loaded` flag to manage lazy loading.
class _CrdtDocumentRegistryItem {
  final String documentId;
  final CRDTDocument document;
  CRDTDocumentStorage? storage;
  bool loaded;

  _CrdtDocumentRegistryItem.lazy({
    required this.documentId,
    required this.document,
  }) : storage = null,
       loaded = false;
}
