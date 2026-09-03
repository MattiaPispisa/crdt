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
/// - [CRDTHive.openSnapshotStorageForDocument]
/// - [CRDTHive.openSnapshotStorageForDocument]
/// - [CRDTHive.openStorageForDocument]
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
