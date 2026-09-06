/// How many ids fit in one `IN (...)`.
///
/// SQLite refuses a statement that binds more variables than
/// `SQLITE_MAX_VARIABLE_NUMBER`. That is 32766 since 3.32, and 999 on the
/// builds before it — the system SQLite of an older Android, say. drift runs
/// on whichever one the executor brings, so the smaller number is the one to
/// respect. One variable is left over for the document id.
const int _idsPerStatement = 900;

/// Cuts [ids] into lists short enough for one SQL statement.
///
/// For the keys a table is not ordered by, which have to be named in an
/// `IN (...)`: past the limit the statement is refused and the whole delete
/// fails. A change is found by its primary key instead, one statement each.
Iterable<List<String>> idChunks(List<String> ids) sync* {
  for (var start = 0; start < ids.length; start += _idsPerStatement) {
    final end = start + _idsPerStatement;
    yield ids.sublist(start, end < ids.length ? end : ids.length);
  }
}
