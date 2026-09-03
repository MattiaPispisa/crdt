/// A Hive storage implementation for CRDT
/// (Conflict-free Replicated Data Type) objects.
///
/// This library provides Hive adapters and storage utilities for persisting
/// CRDT objects like Changes and Snapshots, organized by document.
library;

export 'package:crdt_lf_persistence/crdt_lf_persistence.dart'
    show
        CRDTChangeStorage,
        CRDTDocumentPersistence,
        CRDTDocumentStorage,
        CRDTSnapshotStorage;

export 'src/adapters/change_adapter.dart';
export 'src/adapters/snapshot_adapter.dart';
export 'src/crdt_hive.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/snapshot_storage.dart';
