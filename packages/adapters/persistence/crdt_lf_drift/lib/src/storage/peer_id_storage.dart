import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// Storage utility for the [PeerId] of one document in a drift database.
///
/// One row per document, so several documents share the same table the way
/// their changes and snapshots do.
class CRDTDriftPeerIdStorage implements CRDTPeerIdStorage {
  /// Creates a new [CRDTDriftPeerIdStorage] instance.
  ///
  /// [database] is the drift database used to store the id.
  ///
  /// [documentId] is the document this identity belongs to.
  CRDTDriftPeerIdStorage(this.database, this.documentId);

  /// The drift database used for storing the id.
  final CRDTDriftDatabase database;

  @override
  final String documentId;

  @override
  Future<PeerId?> getPeerId() async {
    final query = database.select(database.peers)
      ..where((row) => row.documentId.equals(documentId))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : PeerId.parse(row.peerId);
  }

  @override
  Future<void> savePeerId(PeerId peerId) {
    return database.into(database.peers).insertOnConflictUpdate(
          PeersCompanion.insert(
            documentId: documentId,
            peerId: peerId.toString(),
          ),
        );
  }
}
