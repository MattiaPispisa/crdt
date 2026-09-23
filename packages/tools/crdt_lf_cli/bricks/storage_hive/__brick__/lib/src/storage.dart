import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

bool _adaptersRegistered = false;

/// Opens the Hive database in [directory].
///
/// Opening the same [directory] again finds the documents stored there.
Future<CRDTStorageBackend> openStorage(String directory) async {
  Hive.init(directory);
  // Hive throws on an adapter registered twice.
  if (!_adaptersRegistered) {
    CRDTHive.initialize();
    _adaptersRegistered = true;
  }
  return CRDTHive.open();
}

/// Closes [backend] and every Hive box it opened.
Future<void> closeStorage(CRDTStorageBackend backend) async {
  await backend.close();
  await CRDTHive.closeAllBoxes();
}
