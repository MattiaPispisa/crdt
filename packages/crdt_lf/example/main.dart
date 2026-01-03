// ignore_for_file: avoid_print example file,
// ignore_for_file: avoid_redundant_argument_values

import 'package:crdt_lf/crdt_lf.dart';

void main() {
  // Create two documents (simulating different peers)
  final doc1 = CRDTDocument(
    peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
  );
  final doc2 = CRDTDocument(
    peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
  );

  // Create text handlers
  final fugueTextDoc1 = CRDTFugueTextHandler(doc1, 'text');
  final fugueTextDoc2 = CRDTFugueTextHandler(doc2, 'text');

  // Initial state
  fugueTextDoc1.insert(0, 'Hello');

  // Sync doc1 to doc2
  var changesDoc1 = doc1.exportChanges();
  doc2.importChanges(changesDoc1);

  // Concurrent edits
  fugueTextDoc1.insert(5, ' World'); // doc1: "Hello World"
  fugueTextDoc2.insert(5, ' Dart'); // doc2: "Hello Dart"

  // Sync both ways
  final changes1After = doc1.exportChanges();
  final changes2After = doc2.exportChanges();

  doc2.importChanges(changes1After);
  doc1.importChanges(changes2After);

  // Both documents will have the same final state
  print(fugueTextDoc1.value); // Prints "Hello World Dart" or "Hello Dart World"
  print(fugueTextDoc2.value); // Prints the same as text1

  // Create list handler
  final list1 = CRDTListHandler<String>(doc1, 'list');
  final list2 = CRDTListHandler<String>(doc2, 'list');

  list1
    ..insert(0, 'Hello')
    ..insert(1, 'World')
    ..insert(2, 'Dart');

  print(list1.value); // Prints ["Hello", "World", "Dart"]

  // sync doc1 to doc2
  changesDoc1 = doc1.exportChanges();
  doc2.importChanges(changesDoc1);

  print(list2.value); // Prints ["Hello", "World", "Dart"]

  // history session
  final historySession = doc1.toTimeTravel();
  final viewListHandler =
      historySession.getHandler<CRDTListHandler<String>, List<String>>(
    (doc) => CRDTListHandler<String>(doc, 'list'),
  );
  print(viewListHandler.value); // Prints ["Hello", "World", "Dart"]

  historySession.previous();
  print(viewListHandler.value); // Prints ["Hello", "World"]

  // transaction
  doc1.runInTransaction(() {
    list1
      ..insert(3, 'Flutter')
      ..insert(4, '!');
  });
  print(list1.value); // Prints ["Hello", "World", "Dart", "Flutter", "!"]

  // snapshot
  // save pruning
  var snapshotDoc1 = doc1.takeSnapshot(pruneHistory: false);
  changesDoc1 = doc1.exportChanges();
  doc2.import(
    snapshot: snapshotDoc1,
    changes: changesDoc1,
    pruneHistory: false,
  );

  // changes are read starting from the snapshot then changed are applied
  print(list2.value); // Prints ["Hello", "World", "Dart", "Flutter", "!"]
  // changes are not pruned
  print(doc1.exportChanges().length); // Prints 8

  // aggressive pruning
  snapshotDoc1 = doc1.takeSnapshot(
    pruneHistory: true,
  );
  // changes are pruned
  doc1.garbageCollect(doc1.getVersionVector());
  print(doc1.exportChanges().length); // Prints 0
}
