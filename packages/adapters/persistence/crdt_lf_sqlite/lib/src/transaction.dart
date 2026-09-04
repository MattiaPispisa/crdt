import 'dart:async';

import 'package:crdt_lf_sqlite/src/storage/document_storage.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// How many savepoints this isolate has opened, so each one gets its own name.
///
/// One shared name is not enough: `RELEASE` and `ROLLBACK TO` both act on the
/// most recent savepoint carrying the name, so two transactions that overlap
/// would each end the other's.
int _savepoints = 0;

/// The asynchronous transaction still running on a database, if there is one.
///
/// An [Expando] and not a field: several [CRDTSqliteDocumentStorage] instances
/// share one connection, and the queue belongs to the connection.
final Expando<Future<void>> _running = Expando<Future<void>>('crdt_lf');

/// {@template crdt_lf_sqlite_batch}
/// The whole batch runs in one transaction, with one prepared statement:
/// either all of it lands, or none of it does.
/// {@endtemplate}
///
/// Runs [body] inside a single SQLite transaction on [database].
///
/// Releases when [body] completes normally, or rolls back and rethrows if it
/// throws. This makes batch operations atomic and avoids one implicit commit
/// per statement.
///
/// A [body] that returns without suspending is carried through without
/// suspending, so nothing else on the connection can run while the
/// transaction is open. This is the normal case: sqlite3 answers every query
/// on the spot.
///
/// A [body] that does suspend waits for whatever transaction is already open
/// on [database], unless it is itself running inside one, which nests instead.
/// Savepoints are a stack on the connection rather than a per-document thing:
/// rolling back to one undoes every write made after it, and a second document
/// writing meanwhile would lose that write without ever seeing an error.
///
/// Built on `SAVEPOINT` rather than `BEGIN`, so it nests: a batch called from
/// inside another transaction keeps its own all-or-nothing behaviour instead
/// of failing on a second `BEGIN`. At the outermost level a `RELEASE` commits,
/// which is what `COMMIT` would have done.
FutureOr<T> runInTransaction<T>(
  sq.Database database,
  FutureOr<T> Function() body,
) {
  // Already inside a transaction on this connection: open a nested savepoint
  // instead of queueing. Waiting here would defer the work past the very
  // transaction that is waiting for it — and a caller that drops the returned
  // future, as the batch methods do, would lose the work altogether.
  if (Zone.current[database] == true) {
    return _begin(database, body);
  }

  final running = _running[database];
  final result = running == null
      ? _begin(database, body)
      : running.then((_) => _begin(database, body));

  if (result is Future<T>) {
    _hold(database, result);
  }
  return result;
}

/// Opens a savepoint, runs [body], and ends the savepoint either way.
FutureOr<T> _begin<T>(sq.Database database, FutureOr<T> Function() body) {
  final savepoint = 'crdt_lf_${_savepoints++}';
  database.execute('SAVEPOINT $savepoint');

  final FutureOr<T> result;
  try {
    // The marker a nested call looks for, carried into the continuations of
    // an asynchronous body as well.
    result = runZoned(body, zoneValues: <Object, Object>{database: true});
  } catch (_) {
    _rollback(database, savepoint);
    rethrow;
  }

  if (result is! Future<T>) {
    database.execute('RELEASE $savepoint');
    return result;
  }

  return result.then(
    (value) {
      database.execute('RELEASE $savepoint');
      return value;
    },
    onError: (Object error, StackTrace stack) {
      _rollback(database, savepoint);
      Error.throwWithStackTrace(error, stack);
    },
  );
}

/// Makes the next transaction on [database] wait for [work].
void _hold(sq.Database database, Future<void> work) {
  // A gate that never carries the error: a caller that ignores a failed
  // transaction must not turn the next one into an unhandled error.
  final gate = work.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  _running[database] = gate;
  gate.whenComplete(() {
    // Only when nothing queued behind it: a later transaction owns the slot.
    if (identical(_running[database], gate)) {
      _running[database] = null;
    }
  });
}

void _rollback(sq.Database database, String savepoint) {
  database
    // Undoes the work, and leaves the savepoint standing...
    ..execute('ROLLBACK TO $savepoint')
    // ...so it still has to be dropped.
    ..execute('RELEASE $savepoint');
}
