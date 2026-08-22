// ignore_for_file: avoid_print just for example

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

Future<void> main() async {
  const changesToInsert = 3;
  const dbLocation = './example/db';
  final documentId = PeerId.parse('784ff372-6f0a-4fe9-8e63-19b72fd18c23');

  Hive.init(dbLocation);
  CRDTHive.initialize();

  final changeStorage = await CRDTHive.openChangeStorageForDocument(
    documentId.toString(),
  );

  final changesToSave = <Change>[];

  final document = CRDTDocument(peerId: documentId)
    ..importChanges(changeStorage.getChanges())
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

  await CRDTHive.closeAllBoxes();

  print('boxes closed');
}
