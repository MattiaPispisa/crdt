/// On the web Hive stores boxes in IndexedDB and ignores the path passed to
/// `Hive.init`, so any string works.
Future<String> hiveTestPath() async => 'crdt_hive_test';
