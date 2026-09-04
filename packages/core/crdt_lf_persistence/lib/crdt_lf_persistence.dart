/// The storage contract behind the `crdt_lf` persistence adapters, and the
/// consumer that keeps a [CRDTDocument] on disk as it changes.
///
/// An adapter implements [CRDTChangeStorage] and [CRDTSnapshotStorage] and
/// hands both back as a [CRDTDocumentStorage], with a [CRDTPeerIdStorage] for
/// the identity the document writes under. A [CRDTStorageBackend] is the whole
/// database: the documents it holds, and the storages of each one.
///
/// [CRDTDocumentPersistence] keeps one document on disk as it changes.
/// Everything an app does with a backend is on it, through
/// [CRDTStorageBackendDocuments]: `openDocument` for one that is going to be
/// edited, `readDocument`, `documentAt` and `copyDocumentTo` for the rest.
/// [CRDTDocumentStorageReading] is the same three on a single storage.
///
/// Nothing here is a store: pick an adapter — `crdt_lf_hive`,
/// `crdt_lf_drift`, `crdt_lf_sqlite` — and it re-exports these symbols
/// alongside its own.
library;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/src/document_persistence.dart';
import 'package:crdt_lf_persistence/src/document_storage_reading.dart';
import 'package:crdt_lf_persistence/src/storage/change_storage.dart';
import 'package:crdt_lf_persistence/src/storage/document_storage.dart';
import 'package:crdt_lf_persistence/src/storage/peer_id_storage.dart';
import 'package:crdt_lf_persistence/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_persistence/src/storage/storage_backend.dart';
import 'package:crdt_lf_persistence/src/storage_backend_documents.dart';

export 'src/document_persistence.dart';
export 'src/document_storage_reading.dart';
export 'src/future_or.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/document_storage.dart';
export 'src/storage/peer_id_storage.dart';
export 'src/storage/snapshot_storage.dart';
export 'src/storage/storage_backend.dart';
export 'src/storage/version_filter.dart';
export 'src/storage_backend_documents.dart';
