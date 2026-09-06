import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:drift/drift.dart';

/// Storage utility for managing [Change] objects in a drift database.
///
/// One row per change, keyed by `(document_id, author, hlc_l, hlc_c)`, with
/// the change itself as an opaque `Change.toBytes()` blob. Every row is
/// scoped to a single document through its `document_id`, so several
/// documents can share the same database.
class CRDTDriftChangeStorage implements CRDTChangeStorage {
  /// Creates a new [CRDTDriftChangeStorage] instance.
  ///
  /// [database] is the drift database used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier for the document these changes
  /// belong to.
  CRDTDriftChangeStorage(this.database, this.documentId);

  /// The drift database used for storing [Change] objects.
  final CRDTDriftDatabase database;

  @override
  final String documentId;

  ChangesCompanion _companion(Change change) {
    return ChangesCompanion.insert(
      documentId: documentId,
      author: change.author.toString(),
      hlcL: change.hlc.l,
      hlcC: change.hlc.c,
      bytes: change.toBytes(),
    );
  }

  /// Matches the single row of [change] in this document.
  Expression<bool> _rowOf(Change change, $ChangesTable row) {
    return row.documentId.equals(documentId) &
        row.author.equals(change.author.toString()) &
        row.hlcL.equals(change.hlc.l) &
        row.hlcC.equals(change.hlc.c);
  }

  /// The rows [vector] has already seen.
  ///
  /// A change is seen when the vector holds an entry for its author and that
  /// entry is at least as new as the change — the same test
  /// [VersionVector.hasSeen] makes, written in SQL. A vector that names no
  /// peer has seen nothing, so it answers false rather than nothing at all.
  ///
  /// Four variables per peer, and no document has a vector long enough for
  /// that to reach the limit SQLite puts on them.
  Expression<bool> _seenBy(VersionVector vector, $ChangesTable row) {
    Expression<bool>? seen;

    for (final entry in vector.entries) {
      final clock = entry.value;
      final term = row.author.equals(entry.key.toString()) &
          (row.hlcL.isSmallerThanValue(clock.l) |
              (row.hlcL.equals(clock.l) &
                  row.hlcC.isSmallerOrEqualValue(clock.c)));
      seen = seen == null ? term : seen | term;
    }

    return seen ?? const Constant(false);
  }

  @override
  Future<void> saveChange(Change change) {
    return database
        .into(database.changes)
        .insertOnConflictUpdate(_companion(change));
  }

  @override
  Future<void> saveChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return;
    }
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        database.changes,
        changes.map(_companion).toList(),
      );
    });
  }

  @override
  Future<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) async {
    // The bounds go to the database, not to `filterByVersion`: the rows that
    // fall outside are never read and never decoded. That is the whole cost
    // of asking a long history what is new.
    final query = database.select(database.changes)
      ..where((row) {
        var filter = row.documentId.equals(documentId);
        if (newerThan != null) {
          filter = filter & _seenBy(newerThan, row).not();
        }
        if (upTo != null) {
          filter = filter & _seenBy(upTo, row);
        }
        return filter;
      });

    final rows = await query.get();
    return rows.map((row) => Change.fromBytes(row.bytes)).toList();
  }

  @override
  Future<bool> deleteChange(Change change) async {
    final deleted = await (database.delete(database.changes)
          ..where((row) => _rowOf(change, row)))
        .go();
    return deleted > 0;
  }

  /// Deletes [changes] in one batch.
  ///
  /// A change that is not stored is not counted, and a change named twice
  /// counts once: the answer is how many rows went, not how many were asked
  /// for.
  @override
  Future<int> deleteChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return Future<int>.value(0);
    }

    // One statement per change, not one `IN (?, ?, ...)` over all of them: a
    // prune hands over everything it removed at once, and SQLite refuses a
    // statement that binds more variables than it allows. A batch has no such
    // ceiling, and every delete here is a hit on the primary key.
    //
    // A batch cannot report how many rows each statement removed, so the
    // count comes from the difference.
    return database.transaction(() async {
      final before = await count;
      await database.batch((batch) {
        for (final change in changes) {
          batch.deleteWhere(
            database.changes,
            (row) => _rowOf(change, row),
          );
        }
      });
      return before - await count;
    });
  }

  @override
  Future<void> clear() async {
    await (database.delete(database.changes)
          ..where((row) => row.documentId.equals(documentId)))
        .go();
  }

  @override
  Future<int> get count async {
    final countExp = database.changes.author.count();
    final query = database.selectOnly(database.changes)
      ..addColumns([countExp])
      ..where(database.changes.documentId.equals(documentId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
