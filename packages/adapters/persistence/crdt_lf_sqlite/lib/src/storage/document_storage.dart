import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

/// Container class for both change and snapshot storage for a document.
class CRDTDocumentStorage {
  /// Creates a new [CRDTDocumentStorage] instance.
  CRDTDocumentStorage({
    required this.changes,
    required this.snapshots,
  }) : assert(
          changes.documentId == snapshots.documentId,
          'changes storage and snapshot storage'
          ' must refer to the same document',
        );

  /// The document id
  String get documentId => changes.documentId;

  /// The change storage for the document.
  final CRDTSqliteChangeStorage changes;

  /// The snapshot storage for the document.
  final CRDTSqliteSnapshotStorage snapshots;
}
