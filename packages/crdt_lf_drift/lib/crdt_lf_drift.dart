/// A Drift database implementation for CRDT
/// (Conflict-free Replicated Data Type) objects.
///
/// This library provides Drift database integration and storage utilities for persisting
/// CRDT objects like Changes and Snapshots, organized by document with reactive streams.
library crdt_lf_drift;

export 'src/converters/hybrid_logical_clock_converter.dart';
export 'src/converters/operation_id_converter.dart';
export 'src/converters/peer_id_converter.dart';
export 'src/converters/version_vector_converter.dart';
export 'src/crdt_drift.dart';
export 'src/database.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/snapshot_storage.dart';
export 'src/tables/changes_table.dart';
export 'src/tables/snapshots_table.dart'; 