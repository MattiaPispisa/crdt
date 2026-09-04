import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_sqlite/src/schema.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// Stores the [PeerId] of one document in a SQLite [sq.Database].
///
/// One row per document, so several documents share the same table the way
/// their changes and snapshots do.
///
/// sqlite3 is synchronous, so both methods answer without ever suspending,
/// and say so in their return type.
class CRDTSqlitePeerIdStorage implements CRDTPeerIdStorage {
  /// Creates a new [CRDTSqlitePeerIdStorage] instance.
  ///
  /// [database] is the SQLite database used to store the id; its schema must
  /// already have been created (see [createSchemaSql]).
  ///
  /// [documentId] is the document this identity belongs to.
  CRDTSqlitePeerIdStorage(this.database, this.documentId);

  /// The SQLite database used for storing the id.
  final sq.Database database;

  @override
  final String documentId;

  @override
  PeerId? getPeerId() {
    final result = database.select(
      'SELECT peer_id FROM $peersTable WHERE document_id = ? LIMIT 1',
      [documentId],
    );
    if (result.isEmpty) {
      return null;
    }
    return PeerId.parse(result.first['peer_id'] as String);
  }

  @override
  void savePeerId(PeerId peerId) {
    database.execute(
      'INSERT OR REPLACE INTO $peersTable (document_id, peer_id) '
      'VALUES (?, ?)',
      [documentId, peerId.toString()],
    );
  }
}
