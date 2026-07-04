import 'dart:io';

/// Returns a real temporary directory path to initialize Hive on the VM,
/// where boxes are persisted on the filesystem.
Future<String> hiveTestPath() async {
  final directory = await Directory.systemTemp.createTemp('crdt_hive_test');
  return directory.path;
}
