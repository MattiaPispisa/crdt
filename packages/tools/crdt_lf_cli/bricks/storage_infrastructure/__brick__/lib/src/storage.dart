import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

import 'storage_backend.dart';

/// Opens the storage backend in [directory].
///
/// [directory] is a folder that exists. A backend that keeps its data
/// elsewhere, such as a database server, can ignore it.
Future<CRDTStorageBackend> openStorage(String directory) async {
  return {{name.pascalCase()}}StorageBackend();
}

/// Closes [backend].
Future<void> closeStorage(CRDTStorageBackend backend) async {
  await backend.close();
}
