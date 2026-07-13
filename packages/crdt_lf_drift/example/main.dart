// ignore_for_file: avoid_print just for example

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';

Future<void> main() async {
  const changesToInsert = 3;
  const dbLocation = './example/crdt_example.db';
  final documentId = PeerId.parse('784ff372-6f0a-4fe9-8e63-19b72fd18c23');

  final storage = CRDTDrift.open(File(dbLocation));
  final changeStorage = storage.changeStorageForDocument(
    documentId.toString(),
  );

  final changesToSave = <Change>[];

  final document = CRDTDocument(peerId: documentId)
    ..importChanges(await changeStorage.getChanges())
    ..localChanges.listen(changesToSave.add);
  final list = CRDTListHandler<String>(document, 'list');

  final length = list.value.length;

  for (var i = length; i < length + changesToInsert; i++) {
    list.insert(i, 'Item $i');
  }

  print('${document.exportChanges().length} changes ');
  print('${list.value}');

  await Future<void>.delayed(const Duration(seconds: 1));

  print('${changesToSave.length} changes to save');

  await changeStorage.saveChanges(changesToSave);

  print('changes saved');

  await storage.close();

  print('database closed');
}
