import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The [PeerId] this device writes under, for one document.
///
/// [CRDTDocument] mints a new [PeerId] when it is given none, so a document
/// reopened without one writes under a new author every time. The version
/// vector then gains an entry that never leaves, and carries it inside every
/// snapshot from then on. Keeping the id here is what makes a reopened
/// document the same writer it was before.
///
/// This is separate from [CRDTDocumentStorage] because it is needed earlier:
/// the id has to exist before the [CRDTDocument] it belongs to, so it cannot
/// come from something opened for that document. An app that keeps no changes
/// and no snapshots on disk can still use this on its own.
///
/// Reusing a stored id is safe. A document advances its clock past every
/// change it applies and every snapshot it imports, so a restored document
/// never mints an operation id twice — as long as it is restored before the
/// first local write, which [CRDTDocumentPersistence.open] guarantees.
///
/// Never let two writers share one id: an operation is identified by peer id
/// plus clock, so two documents writing under one id can mint the same
/// operation twice. One writer per document per device.
abstract interface class CRDTPeerIdStorage {
  /// The document this identity belongs to.
  String get documentId;

  /// The stored [PeerId], or `null` when this device never wrote yet.
  FutureOr<PeerId?> getPeerId();

  /// Stores [peerId], replacing the one before it.
  FutureOr<void> savePeerId(PeerId peerId);
}

/// The read-or-mint step every caller of a [CRDTPeerIdStorage] takes.
extension CRDTPeerIdStorageLoad on CRDTPeerIdStorage {
  /// The stored [PeerId], or a new one, saved before it is returned.
  ///
  /// Call this before building the [CRDTDocument] that writes under it:
  ///
  /// ```dart
  /// final peerId = await peers.loadOrCreate();
  /// final document = CRDTDocument(documentId: 'note', peerId: peerId);
  /// ```
  ///
  /// [CRDTStorageBackendDocuments.openDocument] does this for you.
  FutureOr<PeerId> loadOrCreate() => _loadOr(PeerId.generate);

  /// The stored [PeerId], or [author], saved before it is returned.
  ///
  /// The stored one wins: it is what the document already wrote under, and
  /// writing under a second one would make one device look like two peers.
  /// [author] is the seed for a document that has no identity yet.
  FutureOr<PeerId> loadOr(PeerId author) => _loadOr(() => author);

  /// The stored [PeerId], or what [fallback] gives, saved before it is
  /// returned.
  ///
  /// [fallback] is called only when there is nothing stored, so minting an id
  /// costs nothing on the usual path.
  FutureOr<PeerId> _loadOr(PeerId Function() fallback) {
    return getPeerId().chain((stored) {
      if (stored != null) {
        return stored;
      }
      final minted = fallback();
      return savePeerId(minted).chain((_) => minted);
    });
  }
}
