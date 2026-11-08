// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_hive/src/box_references.dart';

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

  // A second close must not give back a reference another storage holds.
  bool _closed = false;

  /// Closes the two boxes of this document, and only those.
  ///
  /// A box stays open while another storage of the same document still uses
  /// it, so two screens can hold one document. An app that opens one document
  /// after another needs this, or it keeps every box it ever opened.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await BoxReferences.release(_changes.box);
    await BoxReferences.release(_snapshots.box);
  }
}
