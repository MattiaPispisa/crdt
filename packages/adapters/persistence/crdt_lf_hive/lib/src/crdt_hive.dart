import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Main utility class for initializing Hive with CRDT adapters.
///
/// This class provides methods to initialize Hive with all the necessary
/// adapters for CRDT objects and to open the required boxes.
///
/// [Box]es can be managed manually using Hive's native methods:
/// ```dart
/// Hive.openBox<Change>(kBoxName)
/// Hive.openBox<Snapshot>(kBoxName)
/// ```
/// or by leveraging the convenience utilities provided by [CRDTHive]:
///
/// - [CRDTHive.openChangeStorageForDocument]
/// - [CRDTHive.openSnapshotStorageForDocument]
/// - [CRDTHive.openStorageForDocument]
/// - [CRDTHive.openPeerIdStorageForDocument]
///
/// [CRDTHive.open] gives the [CRDTStorageBackend] of this adapter, which is
/// what an app with more than one document wants: it lists them, hands out
/// the storages of each one, and deletes one whole.
class CRDTHive {
  /// Initializes Hive with all CRDT adapters.
  ///
  /// This method must be called before using any CRDT objects with Hive.
  /// It registers the type adapters for:
  /// - [Change] — serialized via [Change.toBytes]
  /// - [Snapshot] — serialized via [Snapshot.toBytes]
  ///
  /// Both [Change] and [Snapshot] are persisted as compact binary blobs using
  /// the self-describing format provided by `crdt_lf`. No recursive Hive
  /// adapters are involved.
  ///
  /// The typeId parameters allow customizing the Hive type IDs for each adapter
  /// if needed to avoid conflicts with other adapters in your application.
  static void initialize({
    int? changeTypeId,
    int? snapshotTypeId,
  }) {
    Hive
      ..registerAdapter(ChangeAdapter(typeId: changeTypeId))
      ..registerAdapter(SnapshotAdapter(typeId: snapshotTypeId));
  }

  /// The [CRDTStorageBackend] of this adapter.
  ///
  /// Everything below is a piece of it; this is the whole database:
  ///
  /// ```dart
  /// CRDTHive.initialize();
  /// final backend = await CRDTHive.open();
  ///
  /// for (final documentId in await backend.documentIds) { /* ... */ }
  /// ```
  ///
  /// [registryBoxName] is the box the document ids live in — see
  /// [CRDTHiveBackend] for why Hive needs one. The other three name the boxes
  /// of the storages, and mean what they mean on the methods below.
  static Future<CRDTHiveBackend> open({
    String changesBoxName = 'changes',
    String snapshotsBoxName = 'snapshots',
    String peerIdsBoxName = 'peer_ids',
    String registryBoxName = 'documents',
  }) {
    return Hive.openBox<String>(registryBoxName).then(
      (registry) => CRDTHiveBackend(
        registry: registry,
        changesBoxName: changesBoxName,
        snapshotsBoxName: snapshotsBoxName,
        peerIdsBoxName: peerIdsBoxName,
      ),
    );
  }

  /// Creates a [CRDTHiveChangeStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Change]s.
  ///
  /// Each document gets its own dedicated box
  /// for better isolation and performance.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [boxName] is the base name of the Hive box to use (defaults to `changes`).
  static Future<CRDTHiveChangeStorage> openChangeStorageForDocument(
    String documentId, {
    String boxName = 'changes',
  }) {
    final documentBoxName = '${boxName}_$documentId';
    return Hive.openBox<Change>(documentBoxName).then(
      (box) => CRDTHiveChangeStorage(box, documentId),
    );
  }

  /// Creates a [CRDTHiveSnapshotStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Snapshot]s.
  ///
  /// Each document gets its own dedicated box
  /// for better isolation and performance.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [boxName] is the base name of the Hive box
  /// to use (defaults to `snapshots`).
  static Future<CRDTHiveSnapshotStorage> openSnapshotStorageForDocument(
    String documentId, {
    String boxName = 'snapshots',
  }) {
    final documentBoxName = '${boxName}_$documentId';
    return Hive.openBox<Snapshot>(documentBoxName).then(
      (box) => CRDTHiveSnapshotStorage(box, documentId),
    );
  }

  /// Creates a [CRDTHivePeerIdStorage] for a specific document.
  ///
  /// Unlike the two above, every document shares one box here, keyed by
  /// document id: a box of its own would cost an open for a single string.
  ///
  /// Read it before building the document, so the document keeps the identity
  /// it wrote under last time:
  ///
  /// ```dart
  /// final peers = await CRDTHive.openPeerIdStorageForDocument('doc-1');
  /// final document = CRDTDocument(
  ///   documentId: 'doc-1',
  ///   peerId: await peers.loadOrCreate(),
  /// );
  /// ```
  ///
  /// [documentId] is the unique identifier for the document.
  /// [boxName] is the name of the shared Hive box (defaults to `peer_ids`).
  static Future<CRDTHivePeerIdStorage> openPeerIdStorageForDocument(
    String documentId, {
    String boxName = 'peer_ids',
  }) {
    return Hive.openBox<String>(boxName).then(
      (box) => CRDTHivePeerIdStorage(box, documentId),
    );
  }

  /// Creates both change and snapshot storage for a specific document.
  ///
  /// Returns a [CRDTDocumentStorage] containing both storage instances
  /// for convenience.
  ///
  /// [documentId] is the unique identifier for the document.
  ///
  /// [changesBoxName] and [snapshotsBoxName] can be customized.
  static Future<CRDTHiveDocumentStorage> openStorageForDocument(
    String documentId, {
    String changesBoxName = 'changes',
    String snapshotsBoxName = 'snapshots',
  }) {
    return Future.wait([
      openChangeStorageForDocument(
        documentId,
        boxName: changesBoxName,
      ),
      openSnapshotStorageForDocument(
        documentId,
        boxName: snapshotsBoxName,
      ),
    ]).then(
      (values) {
        return CRDTHiveDocumentStorage(
          changes: values[0] as CRDTHiveChangeStorage,
          snapshots: values[1] as CRDTHiveSnapshotStorage,
        );
      },
    );
  }

  /// Closes all CRDT-related boxes.
  ///
  /// This method closes all boxes that were opened for CRDT objects.
  /// It's useful for cleanup when shutting down the application.
  static Future<void> closeAllBoxes() {
    return Hive.close();
  }

  /// Deletes a box from disk.
  ///
  /// This permanently deletes the specified box and all its data.
  /// Use with caution as this operation cannot be undone.
  static Future<void> deleteBox(String boxName) {
    return Hive.deleteBoxFromDisk(boxName);
  }

  /// Deletes all data for a specific document by deleting its dedicated boxes.
  ///
  /// This removes the changes, snapshots and stored identity of the document.
  /// Use with caution as this operation cannot be undone.
  ///
  /// It does **not** touch the registry box of [CRDTHiveBackend], which is
  /// what knows the document exists. Call [CRDTHiveBackend.deleteDocument]
  /// instead when there is a backend.
  static Future<void> deleteDocument(
    String documentId, {
    String changesBoxName = 'changes',
    String snapshotsBoxName = 'snapshots',
    String peerIdsBoxName = 'peer_ids',
  }) async {
    final changesDocumentBoxName = '${changesBoxName}_$documentId';
    final snapshotsDocumentBoxName = '${snapshotsBoxName}_$documentId';
    await Future.wait([
      deleteBox(changesDocumentBoxName),
      deleteBox(snapshotsDocumentBoxName),
    ]);

    // Every document shares the identity box, so this one is a key to remove
    // rather than a box to delete.
    final peers = await Hive.openBox<String>(peerIdsBoxName);
    await peers.delete(documentId);
  }
}
