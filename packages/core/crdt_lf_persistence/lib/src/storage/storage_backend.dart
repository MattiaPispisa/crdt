import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// Everything one backend holds: the documents, and what each of them is made
/// of.
///
/// [CRDTDocumentStorage] holds **one** document and knows nothing about the
/// others, which is right for what writes it but not for an app. An app opens
/// a database once and asks it for many documents — list them, open one,
/// delete another. That is this.
///
/// Every adapter has one: `CRDTHive`, `CRDTDrift`, `CRDTSqlite`. Code written
/// against this runs on all of them, so a note app can change backend without
/// changing anything but the line that opens it:
///
/// ```dart
/// final backend = CRDTSqlite.open('notes.db');
///
/// for (final documentId in await backend.documentIds) {
///   final note = await backend.readDocument(documentId);
///   // ...show it in a list
/// }
///
/// final open = await backend.openDocument('note-1');
/// ```
///
/// [CRDTStorageBackendDocuments] is where `openDocument`, `readDocument`,
/// `documentAt` and `copyDocumentTo` live.
///
/// Every method returns a [FutureOr], on the same terms as
/// [CRDTChangeStorage]: a backend that answers without touching the disk
/// returns the value itself and narrows its return type to say so.
abstract interface class CRDTStorageBackend {
  /// The changes and snapshots of [documentId].
  ///
  /// Asking twice for one document is not an error, and the result of the
  /// second call reads what the first one wrote.
  FutureOr<CRDTDocumentStorage> storageForDocument(String documentId);

  /// The [PeerId] this device writes [documentId] under.
  ///
  /// Read it before building the document —
  /// [CRDTStorageBackendDocuments.openDocument] does.
  FutureOr<CRDTPeerIdStorage> peerIdStorageForDocument(String documentId);

  /// Every document this backend holds, in no particular order.
  ///
  /// A document is here once anything about it has been stored, its identity
  /// included. So a document that was opened and never written to is still
  /// listed: it exists, it is empty.
  FutureOr<Set<String>> get documentIds;

  /// Deletes the changes, the snapshots and the stored identity of
  /// [documentId].
  ///
  /// It cannot be undone. Deleting a document that is not there is not an
  /// error. A [CRDTDocumentPersistence] still following that document keeps
  /// writing: dispose it first.
  FutureOr<void> deleteDocument(String documentId);

  /// Closes the backend and everything it opened.
  ///
  /// Calling it twice is not an error.
  FutureOr<void> close();
}
