// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_hive/src/box_references.dart';
import 'package:hive/hive.dart';

/// The [CRDTStorageBackend] of the Hive adapter.
///
/// Open it with [CRDTHive.open], not with this constructor, unless you already
/// hold the registry box.
///
/// **Hive cannot list its boxes.** It answers `boxExists(name)` and nothing
/// else, and this adapter gives every document a box of its own, so the
/// documents have to be written down somewhere. That somewhere is the registry
/// box: the storages this backend hands out put the id in it the first time
/// they write, and [documentIds] reads it back. A document therefore costs one
/// extra row, written with its first change, snapshot or identity.
///
/// Written on the first **write**, not on the open: [readDocument] opens the
/// storage of a document that may not exist, and a document that was only
/// looked at is not one this backend holds.
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

  // One reference for every identity storage this backend hands out.
  Future<Box<String>>? _peerIds;

  // A second close must not give back a reference another backend holds.
  bool _closed = false;

  /// The base name of the per-document box holding the changes.
  final String changesBoxName;

  /// The base name of the per-document box holding the snapshots.
  final String snapshotsBoxName;

  /// The name of the box every document shares for its identity.
  final String peerIdsBoxName;

  @override
  Future<Set<String>> get documentIds async => _registry.values.toSet();

  @override
  Future<CRDTHiveDocumentStorage> storageForDocument(String documentId) {
    return CRDTHive.openStorageForDocument(
      documentId,
      changesBoxName: changesBoxName,
      snapshotsBoxName: snapshotsBoxName,
      onWrite: () => _remember(documentId),
    );
  }

  @override
  Future<CRDTHivePeerIdStorage> peerIdStorageForDocument(
    String documentId,
  ) {
    return (_peerIds ??= BoxReferences.open<String>(peerIdsBoxName)).then(
      (box) => CRDTHivePeerIdStorage(
        box,
        documentId,
        onWrite: () => _remember(documentId),
      ),
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

  /// Closes the registry box and the identity box, unless another backend
  /// still uses them.
  ///
  /// The storages from [peerIdStorageForDocument] stop working with it. The
  /// per-document boxes stay open: whoever asked for them closes them,
  /// through [CRDTDocumentStorage.close]. Use [CRDTHive.closeAllBoxes] to
  /// close everything Hive has open.
  ///
  /// Closing twice is not an error.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await BoxReferences.release(_registry);
    final peerIds = _peerIds;
    if (peerIds != null) {
      await BoxReferences.release(await peerIds);
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
