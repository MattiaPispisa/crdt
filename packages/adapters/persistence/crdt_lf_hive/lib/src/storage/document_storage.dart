import 'package:crdt_lf_hive/src/storage/change_storage.dart';
import 'package:crdt_lf_hive/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The changes and snapshots of one document, in two Hive boxes.
///
/// What [CRDTHive.openStorageForDocument] hands back. It fills in [close] of
/// the shared contract: the boxes belong to this document, so this is the one
/// backend where a document has something of its own to release.
class CRDTHiveDocumentStorage extends CRDTDocumentStorage {
  /// Creates the storage of the document [changes] and [snapshots] belong to.
  CRDTHiveDocumentStorage({
    required CRDTHiveChangeStorage changes,
    required CRDTHiveSnapshotStorage snapshots,
  })  : _changes = changes,
        _snapshots = snapshots,
        super(changes: changes, snapshots: snapshots);

  final CRDTHiveChangeStorage _changes;
  final CRDTHiveSnapshotStorage _snapshots;

  /// Closes the two boxes of this document, and only those.
  ///
  /// [CRDTHive.closeAllBoxes] closes every Hive box the app has open, this
  /// one's included — an app that opens one document after another needs this
  /// instead, or it keeps every box it ever opened.
  @override
  Future<void> close() async {
    await _changes.box.close();
    await _snapshots.box.close();
  }
}
