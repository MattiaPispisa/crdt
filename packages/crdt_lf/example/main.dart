// ignore_for_file: avoid_print example file

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
  final text1 = CRDTFugueTextHandler(doc1, 'text1');
  final text2 = CRDTFugueTextHandler(doc2, 'text1');

  // Initial state
  text1.insert(0, 'Hello');

  // Sync doc1 to doc2
  final changes1 = doc1.exportChanges();
  doc2.importChanges(changes1);

  // Concurrent edits
  text1.insert(5, ' World'); // doc1: "Hello World"
  text2.insert(5, ' Dart'); // doc2: "Hello Dart"

  // Sync both ways
  final changes1After = doc1.exportChanges();
  final changes2After = doc2.exportChanges();

  doc2.importChanges(changes1After);
  doc1.importChanges(changes2After);

  // Both documents will have the same final state
  print(text1.value); // Prints "Hello World Dart" or "Hello Dart World"
  print(text2.value); // Prints the same as text1
}
