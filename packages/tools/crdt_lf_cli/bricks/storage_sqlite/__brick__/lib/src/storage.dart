import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';
import 'package:path/path.dart' as p;

/// Opens the SQLite database `crdt.sqlite` in [directory].
///
/// Opening the same [directory] again finds the documents stored there.
Future<CRDTStorageBackend> openStorage(String directory) async {
  return CRDTSqlite.open(p.join(directory, 'crdt.sqlite'));
}

/// Closes [backend].
Future<void> closeStorage(CRDTStorageBackend backend) async {
  await backend.close();
}
