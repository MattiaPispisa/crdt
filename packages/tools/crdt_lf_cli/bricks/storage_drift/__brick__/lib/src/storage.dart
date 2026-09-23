import 'dart:io';

import 'package:crdt_lf_drift/crdt_lf_drift.dart';
import 'package:path/path.dart' as p;

/// Opens the Drift database `crdt.sqlite` in [directory].
///
/// Opening the same [directory] again finds the documents stored there.
Future<CRDTStorageBackend> openStorage(String directory) async {
  return CRDTDrift.open(File(p.join(directory, 'crdt.sqlite')));
}

/// Closes [backend].
Future<void> closeStorage(CRDTStorageBackend backend) async {
  await backend.close();
}
