import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../converters/hybrid_logical_clock_converter.dart';
import '../converters/operation_id_converter.dart';
import '../converters/peer_id_converter.dart';

/// Drift table for storing [Change] objects.
///
/// This table provides persistence for CRDT changes with document organization.
@DataClassName('ChangeEntity')
class Changes extends Table {
  /// Primary key - combination of document_id and change_id
  TextColumn get id => text()();
  
  /// Document ID this change belongs to
  TextColumn get documentId => text().named('document_id')();
  
  /// Operation ID of the change
  TextColumn get operationId => text().map(const OperationIdConverter())();
  
  /// Hybrid Logical Clock timestamp
  TextColumn get hlc => text().map(const HybridLogicalClockConverter())();
  
  /// Author of the change
  TextColumn get author => text().map(const PeerIdConverter())();
  
  /// Dependencies as a JSON string (set of OperationIds)
  TextColumn get dependencies => text()();
  
  /// Payload data as JSON string
  TextColumn get payload => text()();
  
  /// Timestamp when the change was stored locally
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id, documentId};
  
  @override
  List<Index> get customIndexes => [
    Index('changes_document_id_idx', [documentId]),
    Index('changes_operation_id_idx', [operationId]),
    Index('changes_created_at_idx', [createdAt]),
  ];
} 