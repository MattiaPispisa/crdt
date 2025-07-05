/// Hive adapters for CRDT LF library objects.
///
/// This library provides Hive adapters for persisting CRDT objects:
/// - [Change] and [Snapshot] objects
/// - Their dependencies: [OperationId], [PeerId], [HybridLogicalClock], [VersionVector]
///
/// Usage:
/// ```dart
/// import 'package:crdt_lf_hive/crdt_lf_hive.dart';
/// 
/// // Initialize Hive with adapters
/// CRDTHive.initialize();
/// 
/// // Open storage boxes
/// final changeStorage = CRDTChangeStorage(await CRDTHive.openChangesBox());
/// final snapshotStorage = CRDTSnapshotStorage(await CRDTHive.openSnapshotsBox());
/// ```
library crdt_lf_hive;

// Adapters
export 'src/adapters/peer_id_adapter.dart';
export 'src/adapters/hybrid_logical_clock_adapter.dart';
export 'src/adapters/operation_id_adapter.dart';
export 'src/adapters/version_vector_adapter.dart';
export 'src/adapters/change_adapter.dart';
export 'src/adapters/snapshot_adapter.dart';

// Utilities
export 'src/crdt_hive.dart';
export 'src/change_storage.dart';
export 'src/snapshot_storage.dart'; 