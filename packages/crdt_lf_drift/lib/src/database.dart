import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'tables/changes_table.dart';
import 'tables/snapshots_table.dart';

part 'database.g.dart';

/// Main CRDT Drift database.
///
/// This database manages persistence for CRDT Changes and Snapshots
/// with document-scoped organization.
@DriftDatabase(tables: [Changes, Snapshots])
class CRDTDatabase extends _$CRDTDatabase {
  /// Creates a new [CRDTDatabase] instance.
  ///
  /// [path] is the directory where the database file will be stored.
  /// If not provided, uses the current directory.
  CRDTDatabase([String? path]) : super(_openConnection(path));

  @override
  int get schemaVersion => 1;

  /// Opens a database connection.
  static QueryExecutor _openConnection(String? path) {
    final dbPath = path != null 
        ? p.join(path, 'crdt_database.sqlite')
        : 'crdt_database.sqlite';
    
    return NativeDatabase(File(dbPath));
  }

  /// Creates a database instance with in-memory storage for testing.
  CRDTDatabase.memory() : super(NativeDatabase.memory());

  /// Closes the database connection.
  Future<void> close() => super.close();
} 