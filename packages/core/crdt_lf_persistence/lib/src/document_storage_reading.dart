import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// Reading a [CRDTDocumentStorage] without following it, and copying one.
///
/// [CRDTDocumentPersistence] is for a document that is going to be edited.
/// These are for everything else: a preview, a read-only view, a history view,
/// a backup.
///
/// A [CRDTStorageBackend] has the same three, taking a document id — reach for
/// those when you hold the backend rather than one storage.
extension CRDTDocumentStorageReading on CRDTDocumentStorage {
  /// The document this storage holds, built and handed over, not followed.
  ///
  /// For everything that reads and does not write back. Fifty notes in a list
  /// cost fifty of these instead of fifty [CRDTDocumentPersistence]s, none of
  /// which would ever write anything.
  ///
  /// ```dart
  /// final note = await storage.readDocument();
  /// final title = CRDTFugueTextHandler(note, 'body').value;
  /// ```
  ///
  /// Build the handlers on the document it hands back, as above: a handler
  /// reads its state from the document whenever it is created.
  ///
  /// [onDocument] runs on the fresh document, before anything is read into it,
  /// for the few things that have to be in place first — the factories a
  /// document needs to resolve nested handlers, say.
  ///
  /// [peerId] is the identity the returned document would write under. It does
  /// not matter for reading, and a new one is minted when it is left out —
  /// pass the stored one from [CRDTPeerIdStorage] if this document might
  /// write.
  ///
  /// **Nothing keeps writing this document.** An edit made on it stays in
  /// memory. Use [CRDTStorageBackendDocuments.openDocument] for a document
  /// that is going to be edited.
  ///
  /// Returns without suspending on a storage that reads without suspending, so
  /// a list of notes can be built inside one frame.
  FutureOr<CRDTDocument> readDocument({
    PeerId? peerId,
    void Function(CRDTDocument document)? onDocument,
  }) {
    return _read(
      storage: this,
      peerId: peerId,
      onDocument: onDocument,
      upTo: null,
    );
  }

  /// The document this storage held at [version].
  ///
  /// What a history view reads: the state as it was, rebuilt from the changes
  /// that [version] had already seen.
  ///
  /// ```dart
  /// final before = await storage.documentAt(lastWeek);
  /// ```
  ///
  /// **How far back it reaches is what the log still holds.** A prune deletes
  /// the changes a snapshot covers, so a document that has been compacted
  /// cannot be rebuilt at a version older than its snapshot. It never comes
  /// back quietly wrong: the changes that are left name dependencies the
  /// document cannot resolve and it throws [CausallyNotReadyException], and
  /// where the prune left nothing at all to replay it throws a [StateError]
  /// instead of handing back an empty document.
  ///
  /// A stored snapshot is used only when [version] has seen everything in it —
  /// otherwise it describes a state that had not happened yet at [version].
  ///
  /// [peerId] and [onDocument] mean what they mean on [readDocument], and
  /// nothing keeps writing this document either.
  FutureOr<CRDTDocument> documentAt(
    VersionVector version, {
    PeerId? peerId,
    void Function(CRDTDocument document)? onDocument,
  }) {
    return _read(
      storage: this,
      peerId: peerId,
      onDocument: onDocument,
      upTo: version,
    );
  }

  /// Copies everything this storage holds into [other].
  ///
  /// A backup, a restore, or a move to another adapter — the two storages do
  /// not have to come from the same backend:
  ///
  /// ```dart
  /// await (await hive.storageForDocument('note-1')).copyTo(
  ///   await sqlite.storageForDocument('note-1'),
  ///   fromPeerIds: await hive.peerIdStorageForDocument('note-1'),
  ///   toPeerIds: await sqlite.peerIdStorageForDocument('note-1'),
  /// );
  /// ```
  ///
  /// [CRDTStorageBackendDocuments.copyDocumentTo] is that, in one line.
  ///
  /// Rows already in [other] with the same ids are replaced, so copying twice
  /// leaves what copying once left. What [other] holds and this storage does
  /// not is left alone: clear [other] first for an exact copy.
  ///
  /// Pass [fromPeerIds] and [toPeerIds] to carry the identity across as well.
  /// Without them the copy is the content only, and the document writes under
  /// a new author on the other side — which grows its version vector by an
  /// entry that never leaves.
  ///
  /// **[other] may be the storage of a different document**, which is how a
  /// document is duplicated. Leave the identities out when you do that: two
  /// documents writing under one [PeerId] can mint the same operation id
  /// twice.
  ///
  /// Everything lands in one [CRDTDocumentStorage.transaction] on [other], so
  /// a backend with transactions never holds half a document.
  Future<void> copyTo(
    CRDTDocumentStorage other, {
    CRDTPeerIdStorage? fromPeerIds,
    CRDTPeerIdStorage? toPeerIds,
  }) async {
    final changes = await this.changes.getChanges();
    final snapshots = await this.snapshots.getSnapshots();
    final peerId = fromPeerIds == null ? null : await fromPeerIds.getPeerId();

    await other.transaction<void>(() async {
      await other.changes.saveChanges(changes);
      await other.snapshots.saveSnapshots(snapshots);
    });

    if (peerId != null && toPeerIds != null) {
      await toPeerIds.savePeerId(peerId);
    }
  }
}

/// Reads [storage] into a fresh document, up to [upTo] when it is given.
FutureOr<CRDTDocument> _read({
  required CRDTDocumentStorage storage,
  required PeerId? peerId,
  required void Function(CRDTDocument document)? onDocument,
  required VersionVector? upTo,
}) {
  final document = CRDTDocument(
    documentId: storage.documentId,
    peerId: peerId,
  );
  onDocument?.call(document);

  return storage.changes.getChanges(upTo: upTo).chain(
        (changes) => storage.snapshots.getSnapshots().chain((snapshots) {
          final snapshot = _usableSnapshot(snapshots, upTo);
          if (changes.isEmpty && snapshot == null) {
            // A stored snapshot that this version has not seen means the
            // document held something. Nothing to replay on top of nothing
            // means the prune that came with the snapshot took the history
            // this version needs. An empty document would be a lie.
            if (snapshots.isNotEmpty) {
              throw StateError(
                'the history of ${storage.documentId} before this version has '
                'been pruned, so the document cannot be rebuilt at it',
              );
            }
            return document;
          }

          document.import(
            snapshot: snapshot,
            changes: changes,
            merge: true,
            pruneHistory: false,
          );
          return document;
        }),
      );
}

/// The newest of [snapshots] that [upTo] has seen all of, or the newest of
/// them when there is no bound.
Snapshot? _usableSnapshot(List<Snapshot> snapshots, VersionVector? upTo) {
  if (upTo == null) {
    return newestSnapshot(snapshots);
  }

  return newestSnapshot([
    for (final snapshot in snapshots)
      if (upTo.isStrictlyNewerOrEqualThan(snapshot.versionVector)) snapshot,
  ]);
}
