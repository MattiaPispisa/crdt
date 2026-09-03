import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// Everything one document has on disk: its changes and its snapshots.
///
/// This is what an adapter hands back for a document id, and what
/// [CRDTDocumentPersistence] writes to.
class CRDTDocumentStorage {
  /// Creates the storage of the document [changes] and [snapshots] belong to.
  CRDTDocumentStorage({
    required this.changes,
    required this.snapshots,
  }) : assert(
          changes.documentId == snapshots.documentId,
          'changes and snapshots must belong to the same document',
        );

  /// The document this storage holds.
  String get documentId => changes.documentId;

  /// The stored changes.
  final CRDTChangeStorage changes;

  /// The stored snapshots.
  final CRDTSnapshotStorage snapshots;
}
