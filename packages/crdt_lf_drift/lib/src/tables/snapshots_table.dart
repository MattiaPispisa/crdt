import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';

import '../converters/version_vector_converter.dart';

/// Drift table for storing [Snapshot] objects.
///
/// This table provides persistence for CRDT snapshots with document organization.
@DataClassName('SnapshotEntity')
class Snapshots extends Table {
  /// Primary key - combination of document_id and snapshot_id
  TextColumn get id => text()();
  
  /// Document ID this snapshot belongs to
  TextColumn get documentId => text().named('document_id')();
  
  /// Snapshot ID
  TextColumn get snapshotId => text().named('snapshot_id')();
  
  /// Version vector at the time of snapshot
  TextColumn get versionVector => text().map(const VersionVectorConverter())();
  
  /// Snapshot data as JSON string
  TextColumn get data => text()();
  
  /// Timestamp when the snapshot was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, documentId};
  
  @override
  List<Index> get customIndexes => [
    Index('snapshots_document_id_idx', [documentId]),
    Index('snapshots_snapshot_id_idx', [snapshotId]),
    Index('snapshots_created_at_idx', [createdAt]),
  ];
} 