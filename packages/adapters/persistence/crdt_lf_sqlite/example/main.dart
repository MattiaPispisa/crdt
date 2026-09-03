// ignore_for_file: avoid_print just for example

import 'dart:io' as io;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

Future<void> main() async {
  const itemsToAdd = 3;
  const documentId = '784ff372-6f0a-4fe9-8e63-19b72fd18c23';

  // Resolve the database next to this script so the example works regardless
  // of the current working directory.
  final dbLocation =
      '${io.File.fromUri(io.Platform.script).parent.path}/crdt_example.db';

  final database = CRDTSqlite.open(dbLocation);

  final document = CRDTDocument(documentId: documentId);
  final list = CRDTListHandler<String>(document, 'list');

  // Reads the database into the document, then follows it: everything written
  // from here on is stored without another line of code.
  final persistence = await CRDTDocumentPersistence.open(
    document,
    database.storageForDocument(documentId),
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
  database.close();

  print('now: ${list.value}');
}
