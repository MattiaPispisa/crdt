import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// The [CRDTStorageBackend] of the Hive adapter.
///
/// Open it with [CRDTHive.open], not with this constructor, unless you already
/// hold the registry box.
///
/// **Hive cannot list its boxes.** It answers `boxExists(name)` and nothing
/// else, and this adapter gives every document a box of its own, so the
/// documents have to be written down somewhere. That somewhere is the registry
/// box: [storageForDocument] and [peerIdStorageForDocument] put the id in it,
/// and [documentIds] reads it back. A document therefore costs one extra row,
/// written the first time it is opened.
///
/// A document written by an older version of this adapter — before the
/// registry existed — is not in the box, so [documentIds] does not report it.
/// Its data is untouched, and opening it once puts it back on the list.
class CRDTHiveBackend implements CRDTStorageBackend {
  /// Creates a backend over an already open [registry] box.
  CRDTHiveBackend({
    required Box<String> registry,
    this.changesBoxName = 'changes',
    this.snapshotsBoxName = 'snapshots',
    this.peerIdsBoxName = 'peer_ids',
  }) : _registry = registry;

  final Box<String> _registry;

  /// The base name of the per-document box holding the changes.
  final String changesBoxName;

  /// The base name of the per-document box holding the snapshots.
  final String snapshotsBoxName;

  /// The name of the box every document shares for its identity.
  final String peerIdsBoxName;

  @override
  Future<Set<String>> get documentIds async => _registry.values.toSet();

  @override
  Future<CRDTHiveDocumentStorage> storageForDocument(String documentId) async {
    await _remember(documentId);
    return CRDTHive.openStorageForDocument(
      documentId,
      changesBoxName: changesBoxName,
      snapshotsBoxName: snapshotsBoxName,
    );
  }

  @override
  Future<CRDTHivePeerIdStorage> peerIdStorageForDocument(
    String documentId,
  ) async {
    await _remember(documentId);
    return CRDTHive.openPeerIdStorageForDocument(
      documentId,
      boxName: peerIdsBoxName,
    );
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    await CRDTHive.deleteDocument(
      documentId,
      changesBoxName: changesBoxName,
      snapshotsBoxName: snapshotsBoxName,
      peerIdsBoxName: peerIdsBoxName,
    );
    await _registry.delete(documentId);
  }

  /// Closes the registry box.
  ///
  /// The per-document boxes are not closed here: they are opened one at a
  /// time and closed by whoever asked for them, through
  /// [CRDTDocumentStorage.close]. Use [CRDTHive.closeAllBoxes] to close
  /// everything Hive has open.
  ///
  /// Closing twice is not an error.
  @override
  Future<void> close() async {
    if (_registry.isOpen) {
      await _registry.close();
    }
  }

  /// Writes [documentId] down, so [documentIds] reports it.
  Future<void> _remember(String documentId) {
    if (_registry.containsKey(documentId)) {
      return Future<void>.value();
    }
    return _registry.put(documentId, documentId);
  }
}
