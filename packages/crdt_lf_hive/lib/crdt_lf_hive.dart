/// A Hive storage implementation for CRDT
/// (Conflict-free Replicated Data Type) objects.
///
/// This library provides Hive adapters and storage utilities for persisting
/// CRDT objects like Changes and Snapshots, organized by document.
library crdt_lf_hive;

export 'src/adapters/change_adapter.dart';
export 'src/adapters/fugue_element_id_adapter.dart';
export 'src/adapters/fugue_node_value_adapter.dart';
export 'src/adapters/hybrid_logical_clock_adapter.dart';
export 'src/adapters/operation_id_adapter.dart';
export 'src/adapters/peer_id_adapter.dart';
export 'src/adapters/snapshot_adapter.dart';
export 'src/adapters/version_vector_adapter.dart';
export 'src/crdt_hive.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/snapshot_storage.dart';
