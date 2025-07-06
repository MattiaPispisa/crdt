import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Container class for both change and snapshot storage for a document.
class CRDTDocumentStorage {
  /// Creates a new [CRDTDocumentStorage] instance.
  const CRDTDocumentStorage({
    required this.changes,
    required this.snapshots,
  });

  /// The change storage for the document.
  final CRDTChangeStorage changes;

  /// The snapshot storage for the document.
  final CRDTSnapshotStorage snapshots;
}

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
/// - [CRDTHive.openSnapshotStorageForDocument]
/// - [CRDTHive.openSnapshotStorageForDocument]
/// - [CRDTHive.openStorageForDocument]
class CRDTHive {
  /// Initializes Hive with all CRDT adapters.
  ///
  /// This method must be called before using any CRDT objects with Hive.
  /// It registers all the necessary type adapters for:
  /// - [PeerId]
  /// - [HybridLogicalClock]
  /// - [OperationId]
  /// - [VersionVector]
  /// - [Change]
  /// - [Snapshot]
  ///
  /// [useDataAdapter] more details in [ChangeAdapter].
  static void initialize({bool useDataAdapter = false}) {
    // Register all adapters
    Hive
      ..registerAdapter(PeerIdAdapter())
      ..registerAdapter(HybridLogicalClockAdapter())
      ..registerAdapter(OperationIdAdapter())
      ..registerAdapter(VersionVectorAdapter())
      ..registerAdapter(ChangeAdapter(useDataAdapter: useDataAdapter))
      ..registerAdapter(SnapshotAdapter(useDataAdapter: useDataAdapter));
  }

  /// Creates a [CRDTChangeStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Change]s.
  ///
  /// Each document gets its own dedicated box
  /// for better isolation and performance.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [boxName] is the base name of the Hive box to use (defaults to `changes`).
  static Future<CRDTChangeStorage> openChangeStorageForDocument(
    String documentId, {
    String boxName = 'changes',
  }) {
    final documentBoxName = '${boxName}_$documentId';
    return Hive.openBox<Change>(documentBoxName).then(
      (box) => CRDTChangeStorage(box, documentId),
    );
  }

  /// Creates a [CRDTSnapshotStorage] for a specific document.
  ///
  /// This provides a document-scoped interface for managing [Snapshot]s.
  ///
  /// Each document gets its own dedicated box
  /// for better isolation and performance.
  ///
  /// [documentId] is the unique identifier for the document.
  /// [boxName] is the base name of the Hive box
  /// to use (defaults to `snapshots`).
  static Future<CRDTSnapshotStorage> openSnapshotStorageForDocument(
    String documentId, {
    String boxName = 'snapshots',
  }) {
    final documentBoxName = '${boxName}_$documentId';
    return Hive.openBox<Snapshot>(documentBoxName).then(
      (box) => CRDTSnapshotStorage(box, documentId),
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
  static Future<CRDTDocumentStorage> openStorageForDocument(
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
        return CRDTDocumentStorage(
          changes: values[0] as CRDTChangeStorage,
          snapshots: values[1] as CRDTSnapshotStorage,
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
  /// This removes all changes and snapshots associated with the document.
  /// Use with caution as this operation cannot be undone.
  static Future<void> deleteDocumentData(
    String documentId, {
    String changesBoxName = 'changes',
    String snapshotsBoxName = 'snapshots',
  }) {
    final changesDocumentBoxName = '${changesBoxName}_$documentId';
    final snapshotsDocumentBoxName = '${snapshotsBoxName}_$documentId';
    return Future.wait([
      deleteBox(changesDocumentBoxName),
      deleteBox(snapshotsDocumentBoxName),
    ]);
  }
}
