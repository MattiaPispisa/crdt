// ignore_for_file: avoid_print just for example

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

Future<void> main() async {
  const itemsToAdd = 3;
  const dbLocation = './example/db';
  const documentId = '784ff372-6f0a-4fe9-8e63-19b72fd18c23';

  Hive.init(dbLocation);
  CRDTHive.initialize();

  final document = CRDTDocument(documentId: documentId);
  final list = CRDTListHandler<String>(document, 'list');

  // Reads the boxes into the document, then follows it: everything written
  // from here on is stored without another line of code.
  final persistence = await CRDTDocumentPersistence.open(
    document,
    await CRDTHive.openStorageForDocument(documentId),
  );

  print('read back: ${list.value}');

  final length = list.value.length;
  for (var i = length; i < length + itemsToAdd; i++) {
    list.insert(i, 'Item $i');
  }

  // Writes what is still waiting. Without it the process could end before the
  // delayed write runs.
  await persistence.dispose();
  document.dispose();
  await CRDTHive.closeAllBoxes();

  print('now: ${list.value}');
}
