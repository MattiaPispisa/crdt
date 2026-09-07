import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// A [CRDTDocument] restored from a backend, and the
/// [CRDTDocumentPersistence] that keeps writing it.
///
/// What [CRDTStorageBackendDocuments.openDocument] hands back. Keep both: the
/// document is what the app edits, the persistence is what has to be disposed.
typedef PersistentDocument = ({
  /// The document, already holding what the backend had.
  CRDTDocument document,

  /// What follows the document from here on.
  CRDTDocumentPersistence persistence,
});

/// Opening, reading and copying the documents of a [CRDTStorageBackend].
///
/// The whole of what an app does with a backend, on any adapter. Reach for
/// [CRDTDocumentStorageReading] instead when you hold one storage rather than
/// the backend it came from.
extension CRDTStorageBackendDocuments on CRDTStorageBackend {
  /// Builds [documentId] on top of what this backend already holds.
  ///
  /// Three steps in the order they have to happen, which is the whole point of
  /// this method:
  ///
  /// 1. read the stored [PeerId], so this device stays one author across
  ///    restarts. It has to exist **before** the document, so
  ///    [CRDTDocumentPersistence.open] cannot do it;
  /// 2. build the document;
  /// 3. restore, and follow.
  ///
  /// ```dart
  /// final room = await backend.openDocument(roomId);
  /// final text = CRDTFugueTextHandler(room.document, 'body');
  ///
  /// // Only now: the restored document is what the peer is caught up
  /// // against, so what was written offline reaches it.
  /// await client.connect();
  /// ```
  ///
  /// **Build the handlers on the document it hands back**, as above. A handler
  /// reads its state from the document whenever it is created, so one made
  /// after the restore reads exactly what one made before it would have.
  ///
  /// The identity is always kept: the document writes under the same [PeerId]
  /// it wrote under last time. Minting a new one per open would grow the
  /// version vector by an entry that never leaves, and carry it inside every
  /// snapshot from then on.
  ///
  /// [author] is the identity to use for a document that has none stored yet,
  /// and it is stored. A stored id wins over it: it is what the document
  /// already wrote under, and writing under a second one would make one device
  /// look like two peers.
  ///
  /// [onDocument] runs on the fresh document, before anything is restored into
  /// it. It is for the few things that have to be in place first — a listener
  /// on [CRDTDocument.events] that wants to see the restore, or the factories
  /// a document needs to resolve nested handlers. Handlers do not need it.
  ///
  /// [writeDelay], [compactAfter] and [onError] mean what they mean on
  /// [CRDTDocumentPersistence.open].
  ///
  /// The document is disposed and the failure rethrown when the restore fails,
  /// so a caller never gets half of one back. Nothing is closed: the backend
  /// is the caller's to close, and it usually serves other documents too.
  ///
  /// Use [CRDTDocumentPersistence.open] instead when there is no backend — a
  /// single [CRDTDocumentStorage] written by hand, say. Use [readDocument] for
  /// a document that is only going to be read.
  Future<PersistentDocument> openDocument(
    String documentId, {
    PeerId? author,
    void Function(CRDTDocument document)? onDocument,
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final peers = await peerIdStorageForDocument(documentId);
    final document = CRDTDocument(
      documentId: documentId,
      peerId: author == null
          ? await peers.loadOrCreate()
          : await peers.loadOr(author),
    );

    try {
      onDocument?.call(document);

      final persistence = await CRDTDocumentPersistence.open(
        document,
        await storageForDocument(documentId),
        writeDelay: writeDelay,
        compactAfter: compactAfter,
        onError: onError,
      );
      return (document: document, persistence: persistence);
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }

  /// The document [documentId] holds, built and handed over, not followed.
  ///
  /// [CRDTDocumentStorageReading.readDocument] on the storage of [documentId],
  /// which is where the whole of what it does is written down.
  ///
  /// ```dart
  /// for (final id in await backend.documentIds) {
  ///   final note = await backend.readDocument(id);
  ///   // ...show it in a list
  /// }
  /// ```
  FutureOr<CRDTDocument> readDocument(
    String documentId, {
    PeerId? peerId,
    void Function(CRDTDocument document)? onDocument,
  }) {
    return storageForDocument(documentId).chain(
      (storage) => storage.readDocument(peerId: peerId, onDocument: onDocument),
    );
  }

  /// The document [documentId] held at [version].
  ///
  /// [CRDTDocumentStorageReading.documentAt] on the storage of [documentId],
  /// which is where the limits of it are written down.
  FutureOr<CRDTDocument> documentAt(
    String documentId,
    VersionVector version, {
    PeerId? peerId,
    void Function(CRDTDocument document)? onDocument,
  }) {
    return storageForDocument(documentId).chain(
      (storage) => storage.documentAt(
        version,
        peerId: peerId,
        onDocument: onDocument,
      ),
    );
  }

  /// Copies [documentId] into [other], identity included.
  ///
  /// A backup, a restore, or a move to another adapter, in one line:
  ///
  /// ```dart
  /// await hive.copyDocumentTo(sqlite, 'note-1');
  /// ```
  ///
  /// The identity comes along because the document keeps its id on the other
  /// side: it is the same document, in another place. To duplicate a document
  /// into a **new** one, use [CRDTDocumentStorageReading.copyTo] with the
  /// storage of the new id and leave the identities out — two documents
  /// writing under one [PeerId] can mint the same operation id twice.
  ///
  /// Rows already in [other] with the same ids are replaced, so copying twice
  /// leaves what copying once left.
  Future<void> copyDocumentTo(
    CRDTStorageBackend other,
    String documentId,
  ) async {
    await (await storageForDocument(documentId)).copyTo(
      await other.storageForDocument(documentId),
      fromPeerIds: await peerIdStorageForDocument(documentId),
      toPeerIds: await other.peerIdStorageForDocument(documentId),
    );
  }
}
