/// A Hive storage implementation for CRDT
/// (Conflict-free Replicated Data Type) objects.
///
/// This library provides Hive adapters and storage utilities for persisting
/// CRDT objects like Changes and Snapshots, organized by document. It also
/// stores the `PeerId` each document writes under, so a reopened document is
/// the same author it was before.
library;

// The whole contract, not a curated list of it. Three adapters re-exporting
// the same names by hand is three places to forget one, and a name missing
// from one of them is a symbol its users cannot reach at all.
export 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

export 'src/adapters/change_adapter.dart';
export 'src/adapters/snapshot_adapter.dart';
export 'src/backend.dart';
export 'src/box_name.dart';
export 'src/crdt_hive.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/document_storage.dart';
export 'src/storage/peer_id_storage.dart';
export 'src/storage/snapshot_storage.dart';
