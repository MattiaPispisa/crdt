import 'package:sqlite3/sqlite3.dart' as sq;

/// {@template crdt_lf_sqlite_batch}
/// The whole batch runs in one transaction, with one prepared statement:
/// either all of it lands, or none of it does.
/// {@endtemplate}
///
/// Runs [body] inside a single SQLite transaction on [database].
///
/// Commits when [body] completes normally, or rolls back and rethrows if
/// [body] throws. This makes batch operations atomic (all-or-nothing) and
/// avoids one implicit commit per statement.
void runInTransaction(sq.Database database, void Function() body) {
  database.execute('BEGIN');
  try {
    body();
    database.execute('COMMIT');
  } catch (_) {
    database.execute('ROLLBACK');
    rethrow;
  }
}
