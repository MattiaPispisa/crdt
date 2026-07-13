import 'package:sqlite3/sqlite3.dart' as sq;

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
