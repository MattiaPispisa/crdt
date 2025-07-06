// ignore_for_file: avoid_print just for example

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

Future<void> main() async {
  const changesToInsert = 3;
  const dbLocation = './example/db';
  final documentId = PeerId.parse('784ff372-6f0a-4fe9-8e63-19b72fd18c23');

  Hive.init(dbLocation);
  CRDTHive.initialize(useDataAdapter: true);
  Hive.registerAdapter(ListAdapter());

  final changeStorage = await CRDTHive.openChangeStorageForDocument(
    documentId.toString(),
  );

  final changesToSave = <Change>[];

  final document = CRDTDocument(peerId: documentId)
    ..importChanges(changeStorage.getChanges())
    ..localChanges.listen(changesToSave.add);
  final list = CRDTListHandler<ListValue>(document, 'list');

  print('${document.exportChanges().length} changes imported');

  final length = list.value.length;

  for (var i = length; i < length + changesToInsert; i++) {
    list.insert(
      i,
      ListValue(value: 'Item $i', isDone: false),
    );
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

class ListValue {
  const ListValue({
    required this.value,
    required this.isDone,
  });

  final String value;
  final bool isDone;

  @override
  String toString() => 'ListValue(value: $value, isDone: $isDone)';
}

class ListAdapter extends TypeAdapter<ListValue> {
  @override
  final int typeId = 200;

  @override
  ListValue read(BinaryReader reader) {
    return ListValue(
      value: reader.readString(),
      isDone: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, ListValue obj) {
    writer
      ..writeString(obj.value)
      ..writeBool(obj.isDone);
  }
}
