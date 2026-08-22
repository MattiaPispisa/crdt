// Provides a Hive init path that works on both the VM (real temp directory)
// and the web (IndexedDB, path ignored), via a conditional import.
export 'hive_test_path_web.dart' if (dart.library.io) 'hive_test_path_io.dart';
