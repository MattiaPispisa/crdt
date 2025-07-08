import 'dart:io';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

void main() {
  late String tempDir;

  setUpAll(() async {
    // Initialize adapters only once for all tests
    CRDTHive.initialize(useDataAdapter: true);
    Hive
      ..registerAdapter(ListValueAdapter())
      ..registerAdapter(ObjectValueAdapter());
  });

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('crdt_hive_test');
    tempDir = directory.path;
    Hive.init(tempDir);
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    await Hive.deleteFromDisk();
  });

  group('CRDTHive Integration Tests', () {
    group('Single document', () {
      late List<Change> changesToSave;

      late String documentId;
      late CRDTDocument document;

      late CRDTListHandler<ListValue> list;
      late CRDTMapHandler<ObjectValue> map;
      late CRDTTextHandler text;
      late CRDTFugueTextHandler fugueText;

      setUp(() {
        changesToSave = [];

        documentId = '09c86fd2-20e7-4290-9bb9-d30bfd542e5b';
        document = CRDTDocument(peerId: PeerId.parse(documentId))
          ..localChanges.listen(changesToSave.add);

        list = CRDTListHandler<ListValue>(document, 'list');
        map = CRDTMapHandler<ObjectValue>(document, 'map');
        text = CRDTTextHandler(document, 'text');
        fugueText = CRDTFugueTextHandler(document, 'fugueText');
      });

      test('should save and load changes correctly', () async {
        var changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        expect(changeStorage.count, equals(0));

        // create some changes for different handlers
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        map.set(
          'object',
          const ObjectValue(height: 100, width: 100, offsetX: 0, offsetY: 0),
        );

        text.insert(0, 'Hello');
        fugueText.insert(0, 'World');

        // wait stream add and save changes
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          () => changeStorage.saveChanges(changesToSave),
          returnsNormally,
        );

        await CRDTHive.closeAllBoxes();

        changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);

        expect(changeStorage.count, greaterThan(0));
        expect(changeStorage.getChanges(), isNotEmpty);

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage.getChanges());

        final newList = CRDTListHandler<ListValue>(newDocument, 'list');

        expect(newList.length, 2);
        expect(newList[0].value, 'a');
        expect(newList[1].value, 'b');
      });

      test('should save and load snapshots correctly', () async {
        var snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(snapshotStorage.count, isZero);

        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        final snapshot1 = document.takeSnapshot();

        map.set(
          'object',
          const ObjectValue(height: 100, width: 100, offsetX: 0, offsetY: 0),
        );

        final snapshot2 = document.takeSnapshot();

        text.insert(0, 'Hello');
        fugueText.insert(0, 'World');

        final snapshot3 = document.takeSnapshot();

        await snapshotStorage.saveSnapshots([snapshot1, snapshot2, snapshot3]);

        await CRDTHive.closeAllBoxes();

        snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(snapshotStorage.count, equals(3));
        expect(snapshotStorage.getSnapshots().length, equals(3));

        expect(snapshotStorage.containsSnapshot(snapshot1.id), isTrue);
        expect(snapshotStorage.containsSnapshot(snapshot2.id), isTrue);
        expect(snapshotStorage.containsSnapshot(snapshot3.id), isTrue);

        final snapshot1Data = snapshotStorage.getSnapshot(snapshot1.id);

        expect(snapshot1Data, isNotNull);
        expect(snapshot1Data!.data, isNotEmpty);
        expect(snapshot1Data.versionVector.entries, isNotEmpty);

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importSnapshot(snapshot1);

        final newList = CRDTListHandler<ListValue>(newDocument, 'list');

        expect(newList.length, 2);
        expect(newList[0].value, 'a');
        expect(newList[1].value, 'b');
      });

      test('should delete changes correctly', () async {
        final changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        expect(changeStorage.count, equals(0));

        // create some changes for different handlers
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        // wait stream add and save changes
        await Future<void>.delayed(Duration.zero);

        await changeStorage.saveChange(changesToSave.first);
        await changeStorage.saveChange(changesToSave.last);

        expect(changeStorage.count, equals(2));

        await changeStorage.deleteChange(changesToSave.first);

        expect(changeStorage.count, equals(1));
      });

      test('should delete snapshots correctly', () async {
        final snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(snapshotStorage.count, equals(0));

        final snapshot1 = document.takeSnapshot();

        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        final snapshot2 = document.takeSnapshot();

        await snapshotStorage.saveSnapshot(snapshot1);
        await snapshotStorage.saveSnapshot(snapshot2);

        expect(snapshotStorage.count, equals(2));

        await snapshotStorage.deleteSnapshot(snapshot1.id);

        expect(snapshotStorage.count, equals(1));
        expect(snapshotStorage.getSnapshots().length, equals(1));
        expect(snapshotStorage.containsSnapshot(snapshot1.id), isFalse);
        expect(snapshotStorage.containsSnapshot(snapshot2.id), isTrue);
      });
    });

    group('Multiple documents', () {
      late List<Change> changesToSaveDocument1;
      late List<Change> changesToSaveDocument2;

      late CRDTDocument document1;
      late CRDTDocument document2;

      late CRDTListHandler<ListValue> list1;
      late CRDTListHandler<ListValue> list2;

      setUp(() {
        changesToSaveDocument1 = [];
        changesToSaveDocument2 = [];

        document1 = CRDTDocument(
          peerId: PeerId.parse('5fe9139e-6c1d-4a6b-a767-4071b1e379dd'),
        )..localChanges.listen(changesToSaveDocument1.add);
        document2 = CRDTDocument(
          peerId: PeerId.parse('32f8d819-8b64-4cf2-a239-e2e6414b19ef'),
        )..localChanges.listen(changesToSaveDocument2.add);

        list1 = CRDTListHandler<ListValue>(document1, 'list');
        list2 = CRDTListHandler<ListValue>(document2, 'list');
      });

      test('should handle multiple documents independently', () async {
        var changeStorage1 = await CRDTHive.openChangeStorageForDocument(
          document1.peerId.toString(),
        );
        var changeStorage2 = await CRDTHive.openChangeStorageForDocument(
          document2.peerId.toString(),
        );

        list1
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        list2
          ..insert(0, const ListValue(value: 'c'))
          ..insert(1, const ListValue(value: 'd'));

        await Future<void>.delayed(Duration.zero);

        await changeStorage1.saveChanges(changesToSaveDocument1);
        await changeStorage2.saveChanges(changesToSaveDocument2);

        expect(changeStorage1.count, equals(2));
        expect(changeStorage2.count, equals(2));

        await CRDTHive.closeAllBoxes();

        changeStorage1 = await CRDTHive.openChangeStorageForDocument(
          document1.peerId.toString(),
        );
        changeStorage2 = await CRDTHive.openChangeStorageForDocument(
          document2.peerId.toString(),
        );

        final newDocument1 = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage1.getChanges());

        final newDocument2 = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage2.getChanges());

        final newList1 = CRDTListHandler<ListValue>(newDocument1, 'list');
        final newList2 = CRDTListHandler<ListValue>(newDocument2, 'list');

        expect(newList1.length, equals(2));
        expect(newList2.length, equals(2));
        expect(newList1[0].value, 'a');
      });
    });
  });
}

class ListValue {
  const ListValue({
    required this.value,
  });

  final String value;

  @override
  String toString() => 'ListValue(value: $value)';
}

class ObjectValue {
  const ObjectValue({
    required this.height,
    required this.width,
    required this.offsetX,
    required this.offsetY,
  });

  final double height;
  final double width;
  final double offsetX;
  final double offsetY;

  @override
  String toString() => 'MapValue(height: $height, width: $width)';
}

class ListValueAdapter extends TypeAdapter<ListValue> {
  @override
  final int typeId = 200;

  @override
  ListValue read(BinaryReader reader) {
    return ListValue(value: reader.readString());
  }

  @override
  void write(BinaryWriter writer, ListValue obj) {
    writer.writeString(obj.value);
  }
}

class ObjectValueAdapter extends TypeAdapter<ObjectValue> {
  @override
  final int typeId = 201;

  @override
  ObjectValue read(BinaryReader reader) {
    return ObjectValue(
      height: reader.readDouble(),
      width: reader.readDouble(),
      offsetX: reader.readDouble(),
      offsetY: reader.readDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, ObjectValue obj) {
    writer
      ..writeDouble(obj.height)
      ..writeDouble(obj.width)
      ..writeDouble(obj.offsetX)
      ..writeDouble(obj.offsetY);
  }
}
