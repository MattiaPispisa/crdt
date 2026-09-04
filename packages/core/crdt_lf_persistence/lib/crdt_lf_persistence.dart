/// The storage contract behind the `crdt_lf` persistence adapters, and the
/// consumer that keeps a [CRDTDocument] on disk as it changes.
///
/// An adapter implements [CRDTChangeStorage] and [CRDTSnapshotStorage] and
/// hands both back as a [CRDTDocumentStorage].
/// [CRDTDocumentPersistence] does the rest, on any of them.
/// [CRDTPeerIdStorage] stands on its own: it keeps the identity a document
/// writes under, and is needed before that document exists.
///
/// Nothing here is a store: pick an adapter — `crdt_lf_hive`,
/// `crdt_lf_drift`, `crdt_lf_sqlite` — and it re-exports these symbols
/// alongside its own.
library;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/src/document_persistence.dart';
import 'package:crdt_lf_persistence/src/storage/change_storage.dart';
import 'package:crdt_lf_persistence/src/storage/document_storage.dart';
import 'package:crdt_lf_persistence/src/storage/peer_id_storage.dart';
import 'package:crdt_lf_persistence/src/storage/snapshot_storage.dart';

export 'src/document_persistence.dart';
export 'src/future_or.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/document_storage.dart';
export 'src/storage/peer_id_storage.dart';
export 'src/storage/snapshot_storage.dart';
export 'src/storage/version_filter.dart';
