import 'dart:io';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTHive with data adapter', () {
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

    group('Single document', () {
      late List<Change> changesToSave;

      late String documentId;
      late CRDTDocument document;

      late CRDTListHandler<ListValue> list;
      late CRDTMapHandler<ObjectValue> map;
      late CRDTTextHandler text;
      late CRDTFugueTextHandler fugueText;
      late CRDTORSetHandler<String> orSet;
      late CRDTORMapHandler<String, int> orMap;

      setUp(() {
        changesToSave = [];

        documentId = '09c86fd2-20e7-4290-9bb9-d30bfd542e5b';
        document = CRDTDocument(peerId: PeerId.parse(documentId))
          ..localChanges.listen(changesToSave.add);

        list = CRDTListHandler<ListValue>(document, 'list');
        map = CRDTMapHandler<ObjectValue>(document, 'map');
        text = CRDTTextHandler(document, 'text');
        fugueText = CRDTFugueTextHandler(document, 'fugueText');
        orSet = CRDTORSetHandler(document, 'orSet');
        orMap = CRDTORMapHandler(document, 'orMap');
      });

      test('should save and load changes correctly', () async {
        // Open change storage for the document
        var changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        // Verify storage is initially empty
        expect(
          changeStorage.count,
          equals(0),
          reason: 'Change storage should be empty when first opened',
        );
        expect(
          changeStorage.isEmpty,
          isTrue,
          reason: 'isEmpty should return true for empty storage',
        );
        expect(
          changeStorage.isNotEmpty,
          isFalse,
          reason: 'isNotEmpty should return false for empty storage',
        );

        // Create changes for all handlers to test complete serialization

        // Test CRDTListHandler with custom ListValue objects
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        // Test CRDTMapHandler with custom ObjectValue objects
        map.set(
          'object',
          const ObjectValue(
            height: 100,
            width: 100,
            offsetX: 0,
            offsetY: 0,
          ),
        );

        // Test CRDTTextHandler with string insertion
        text.insert(0, 'Hello');

        // Test CRDTFugueTextHandler with string insertion
        fugueText.insert(0, 'World');

        // Test CRDTORSetHandler with multiple additions
        orSet
          ..add('a')
          ..add('b');

        // Test CRDTORMapHandler with multiple put operations
        orMap
          ..put('a', 1)
          ..put('b', 2);

        // Wait for local changes stream to emit all changes
        await Future<void>.delayed(Duration.zero);

        // Verify changes were captured
        expect(
          changesToSave,
          isNotEmpty,
          reason: 'Local changes stream should have captured all operations',
        );
        expect(
          changesToSave.length,
          greaterThan(5),
          reason: 'Should have changes from all 6 handlers',
        );

        // Save all changes to Hive storage
        await expectLater(
          () => changeStorage.saveChanges(changesToSave),
          returnsNormally,
          reason: 'Saving changes should complete without errors',
        );

        // Close and reopen storage to verify persistence
        await CRDTHive.closeAllBoxes();
        changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);

        // Verify changes were persisted correctly
        expect(
          changeStorage.count,
          greaterThan(0),
          reason: 'Storage should contain the saved changes after reopening',
        );
        expect(
          changeStorage.count,
          equals(changesToSave.length),
          reason: 'Number of stored changes should match saved changes',
        );
        expect(
          changeStorage.isEmpty,
          isFalse,
          reason: 'Storage should not be empty after saving changes',
        );
        expect(
          changeStorage.isNotEmpty,
          isTrue,
          reason: 'isNotEmpty should return true after saving changes',
        );
        expect(
          changeStorage.getChanges(),
          isNotEmpty,
          reason: 'getChanges() should return non-empty list',
        );

        // Import changes into a new document to verify deserialization
        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage.getChanges());

        // Verify CRDTListHandler data was correctly deserialized
        final newList = CRDTListHandler<ListValue>(newDocument, 'list');
        expect(
          newList.length,
          equals(2),
          reason: 'List should contain 2 items after import',
        );
        expect(
          newList[0].value,
          equals('a'),
          reason: 'First list item should be "a"',
        );
        expect(
          newList[1].value,
          equals('b'),
          reason: 'Second list item should be "b"',
        );

        // Verify CRDTMapHandler data with custom objects was correctly
        // deserialized
        final newMap = CRDTMapHandler<ObjectValue>(newDocument, 'map');
        expect(
          newMap.value,
          {
            'object': const ObjectValue(
              height: 100,
              width: 100,
              offsetX: 0,
              offsetY: 0,
            ),
          },
          reason: 'Map should contain the ObjectValue with correct properties',
        );
        expect(
          newMap['object']?.height,
          equals(100),
          reason: 'Object height should be preserved',
        );
        expect(
          newMap['object']?.width,
          equals(100),
          reason: 'Object width should be preserved',
        );

        // Verify CRDTTextHandler data was correctly deserialized
        final newText = CRDTTextHandler(newDocument, 'text');
        expect(
          newText.value,
          equals('Hello'),
          reason: 'Text handler should contain "Hello"',
        );
        expect(
          newText.length,
          equals(5),
          reason: 'Text length should be 5',
        );

        // Verify CRDTFugueTextHandler data was correctly deserialized
        final newFugueText = CRDTFugueTextHandler(newDocument, 'fugueText');
        expect(
          newFugueText.value,
          equals('World'),
          reason: 'FugueText handler should contain "World"',
        );
        expect(
          newFugueText.length,
          equals(5),
          reason: 'FugueText length should be 5',
        );

        // Verify CRDTORSetHandler data was correctly deserialized
        final newOrSet = CRDTORSetHandler<String>(newDocument, 'orSet');
        expect(
          newOrSet.value,
          equals({'a', 'b'}),
          reason: 'ORSet should contain both "a" and "b"',
        );
        expect(
          newOrSet.value.length,
          equals(2),
          reason: 'ORSet should have 2 elements',
        );

        // Verify CRDTORMapHandler data was correctly deserialized
        final newOrMap = CRDTORMapHandler<String, int>(newDocument, 'orMap');
        expect(
          newOrMap.value,
          equals({'a': 1, 'b': 2}),
          reason: 'ORMap should contain correct key-value pairs',
        );
        expect(
          newOrMap['a'],
          equals(1),
          reason: 'ORMap key "a" should have value 1',
        );
        expect(
          newOrMap['b'],
          equals(2),
          reason: 'ORMap key "b" should have value 2',
        );
      });

      test('should save and load snapshots correctly', () async {
        // Open snapshot storage for the document
        var snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        // Verify storage is initially empty
        expect(
          snapshotStorage.count,
          isZero,
          reason: 'Snapshot storage should be empty when first opened',
        );
        expect(
          snapshotStorage.isEmpty,
          isTrue,
          reason: 'isEmpty should return true for empty storage',
        );
        expect(
          snapshotStorage.isNotEmpty,
          isFalse,
          reason: 'isNotEmpty should return false for empty storage',
        );

        // Create first snapshot with list data
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        final snapshot1 = document.takeSnapshot();
        expect(
          snapshot1.data,
          isNotEmpty,
          reason: 'Snapshot1 should contain data from list handler',
        );
        expect(
          snapshot1.data.containsKey('list'),
          isTrue,
          reason: 'Snapshot1 should include list handler data',
        );

        // Add more data and create second snapshot
        map.set(
          'object',
          const ObjectValue(
            height: 100,
            width: 100,
            offsetX: 0,
            offsetY: 0,
          ),
        );

        orSet
          ..add('a')
          ..add('b');

        orMap
          ..put('a', 1)
          ..put('b', 2);

        final snapshot2 = document.takeSnapshot();
        expect(
          snapshot2.data.length,
          equals(6),
          reason: 'Snapshot2 should include all 6 handlers',
        );
        expect(
          snapshot2.data.containsKey('map'),
          isTrue,
          reason: 'Snapshot2 should include map handler data',
        );
        expect(
          snapshot2.data.containsKey('orSet'),
          isTrue,
          reason: 'Snapshot2 should include orSet handler data',
        );

        // Add text data and create third snapshot
        text.insert(0, 'Hello');
        fugueText.insert(0, 'World');

        final snapshot3 = document.takeSnapshot();
        expect(
          snapshot3.data.length,
          equals(6),
          reason: 'Snapshot3 should include all 6 handlers',
        );
        expect(
          snapshot3.data.containsKey('text'),
          isTrue,
          reason: 'Snapshot3 should include text handler data',
        );
        expect(
          snapshot3.data.containsKey('fugueText'),
          isTrue,
          reason: 'Snapshot3 should include fugueText handler data',
        );

        // Save all three snapshots to storage
        await snapshotStorage.saveSnapshots([snapshot1, snapshot2, snapshot3]);

        // Close and reopen storage to verify persistence
        await CRDTHive.closeAllBoxes();
        snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        // Verify all snapshots were persisted
        expect(
          snapshotStorage.count,
          equals(3),
          reason: 'Storage should contain all 3 saved snapshots',
        );
        expect(
          snapshotStorage.isEmpty,
          isFalse,
          reason: 'Storage should not be empty after saving snapshots',
        );
        expect(
          snapshotStorage.isNotEmpty,
          isTrue,
          reason: 'isNotEmpty should return true after saving snapshots',
        );
        expect(
          snapshotStorage.getSnapshots().length,
          equals(3),
          reason: 'getSnapshots() should return all 3 snapshots',
        );

        // Verify each snapshot can be found by ID
        expect(
          snapshotStorage.containsSnapshot(snapshot1.id),
          isTrue,
          reason: 'Storage should contain snapshot1 by ID',
        );
        expect(
          snapshotStorage.containsSnapshot(snapshot2.id),
          isTrue,
          reason: 'Storage should contain snapshot2 by ID',
        );
        expect(
          snapshotStorage.containsSnapshot(snapshot3.id),
          isTrue,
          reason: 'Storage should contain snapshot3 by ID',
        );

        // Retrieve and verify snapshot1 data
        final snapshot1Data = snapshotStorage.getSnapshot(snapshot1.id);
        expect(
          snapshot1Data,
          isNotNull,
          reason: 'Snapshot1 should be retrievable by ID',
        );
        expect(
          snapshot1Data!.data,
          isNotEmpty,
          reason: 'Snapshot1 data should not be empty',
        );
        expect(
          snapshot1Data.versionVector.entries,
          isNotEmpty,
          reason: 'Snapshot1 version vector should contain entries',
        );
        expect(
          snapshot1Data.id,
          equals(snapshot1.id),
          reason: 'Retrieved snapshot1 should have matching ID',
        );

        // Import the last snapshot (contains all data) into a new document
        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importSnapshot(snapshot3);

        // Verify list data from snapshot
        final newList = CRDTListHandler<ListValue>(newDocument, 'list');
        expect(
          newList.length,
          equals(2),
          reason: 'List should have 2 items from snapshot',
        );
        expect(
          newList[0].value,
          equals('a'),
          reason: 'First list item should be "a" from snapshot',
        );
        expect(
          newList[1].value,
          equals('b'),
          reason: 'Second list item should be "b" from snapshot',
        );

        // Verify map data with custom objects from snapshot
        final newMap = CRDTMapHandler<ObjectValue>(newDocument, 'map');
        expect(
          newMap.value,
          {
            'object': const ObjectValue(
              height: 100,
              width: 100,
              offsetX: 0,
              offsetY: 0,
            ),
          },
          reason: 'Map should contain ObjectValue from snapshot',
        );
        expect(
          newMap.value.containsKey('object'),
          isTrue,
          reason: 'Map should have "object" key from snapshot',
        );

        // Verify ORSet data from snapshot
        final newOrSet = CRDTORSetHandler<String>(newDocument, 'orSet');
        expect(
          newOrSet.value,
          equals({'a', 'b'}),
          reason: 'ORSet should contain both elements from snapshot',
        );
        expect(
          newOrSet.value.contains('a'),
          isTrue,
          reason: 'ORSet should contain "a" from snapshot',
        );
        expect(
          newOrSet.value.contains('b'),
          isTrue,
          reason: 'ORSet should contain "b" from snapshot',
        );

        // Verify ORMap data from snapshot
        final newOrMap = CRDTORMapHandler<String, int>(newDocument, 'orMap');
        expect(
          newOrMap.value,
          equals({'a': 1, 'b': 2}),
          reason: 'ORMap should contain all entries from snapshot',
        );
        expect(
          newOrMap.containsKey('a'),
          isTrue,
          reason: 'ORMap should have key "a" from snapshot',
        );
        expect(
          newOrMap.containsKey('b'),
          isTrue,
          reason: 'ORMap should have key "b" from snapshot',
        );
      });

      test('should delete changes correctly', () async {
        // Open change storage for deletion test
        final changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        // Verify storage starts empty
        expect(
          changeStorage.count,
          equals(0),
          reason: 'Storage should be empty before adding changes',
        );
        expect(
          changeStorage.isEmpty,
          isTrue,
          reason: 'isEmpty should be true initially',
        );
        expect(
          changeStorage.isNotEmpty,
          isFalse,
          reason: 'isNotEmpty should be false initially',
        );

        // Create changes to test deletion
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        // Wait for local changes stream to emit changes
        await Future<void>.delayed(Duration.zero);

        // Verify we have changes to work with
        expect(
          changesToSave.length,
          equals(2),
          reason: 'Should have captured 2 changes from list operations',
        );

        // Save individual changes
        await changeStorage.saveChange(changesToSave.first);
        await changeStorage.saveChange(changesToSave.last);

        // Verify both changes were saved
        expect(
          changeStorage.count,
          equals(2),
          reason: 'Storage should contain 2 saved changes',
        );
        expect(
          changeStorage.isEmpty,
          isFalse,
          reason: 'Storage should not be empty after saving',
        );
        expect(
          changeStorage.isNotEmpty,
          isTrue,
          reason: 'isNotEmpty should be true after saving',
        );

        // Store the first change ID for verification
        final firstChangeId = changesToSave.first.id;
        final lastChangeId = changesToSave.last.id;

        // Delete the first change
        await changeStorage.deleteChange(changesToSave.first);

        // Verify deletion was successful
        expect(
          changeStorage.count,
          equals(1),
          reason: 'Storage should contain 1 change after deletion',
        );
        expect(
          changeStorage.getChanges().length,
          equals(1),
          reason: 'getChanges() should return 1 change after deletion',
        );

        // Verify the correct change was deleted
        final remainingChanges = changeStorage.getChanges();
        expect(
          remainingChanges.first.id,
          equals(lastChangeId),
          reason: 'The remaining change should be the last one',
        );
        expect(
          remainingChanges.any((c) => c.id == firstChangeId),
          isFalse,
          reason: 'First change should not be in storage after deletion',
        );
      });

      test('should delete snapshots correctly', () async {
        // Open snapshot storage for deletion test
        final snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        // Verify storage starts empty
        expect(
          snapshotStorage.count,
          equals(0),
          reason: 'Snapshot storage should be empty initially',
        );
        expect(
          snapshotStorage.isEmpty,
          isTrue,
          reason: 'isEmpty should be true initially',
        );
        expect(
          snapshotStorage.isNotEmpty,
          isFalse,
          reason: 'isNotEmpty should be false initially',
        );

        // Create first snapshot (all handlers with initial empty states)
        final snapshot1 = document.takeSnapshot();
        expect(
          snapshot1.data,
          isNotEmpty,
          reason: 'Snapshot1 contains initial states from all handlers',
        );
        expect(
          snapshot1.data.length,
          equals(6),
          reason: 'Snapshot1 should include all 6 registered handlers',
        );

        // Add data and create second snapshot
        list
          ..insert(0, const ListValue(value: 'a'))
          ..insert(1, const ListValue(value: 'b'));

        final snapshot2 = document.takeSnapshot();
        expect(
          snapshot2.data,
          isNotEmpty,
          reason: 'Snapshot2 should contain list data',
        );
        expect(
          snapshot2.versionVector.isStrictlyNewerOrEqualThan(
            snapshot1.versionVector,
          ),
          isTrue,
          reason: 'Snapshot2 version should be newer than snapshot1',
        );

        // Save both snapshots
        await snapshotStorage.saveSnapshot(snapshot1);
        await snapshotStorage.saveSnapshot(snapshot2);

        // Verify both snapshots were saved
        expect(
          snapshotStorage.count,
          equals(2),
          reason: 'Storage should contain 2 saved snapshots',
        );
        expect(
          snapshotStorage.isEmpty,
          isFalse,
          reason: 'Storage should not be empty after saving',
        );
        expect(
          snapshotStorage.isNotEmpty,
          isTrue,
          reason: 'isNotEmpty should be true after saving',
        );

        // Verify both snapshots can be found
        expect(
          snapshotStorage.containsSnapshot(snapshot1.id),
          isTrue,
          reason: 'Snapshot1 should be in storage before deletion',
        );
        expect(
          snapshotStorage.containsSnapshot(snapshot2.id),
          isTrue,
          reason: 'Snapshot2 should be in storage before deletion',
        );

        // Delete the first snapshot
        await snapshotStorage.deleteSnapshot(snapshot1.id);

        // Verify deletion was successful
        expect(
          snapshotStorage.count,
          equals(1),
          reason: 'Storage should contain 1 snapshot after deletion',
        );
        expect(
          snapshotStorage.getSnapshots().length,
          equals(1),
          reason: 'getSnapshots() should return 1 snapshot after deletion',
        );

        // Verify snapshot1 was deleted
        expect(
          snapshotStorage.containsSnapshot(snapshot1.id),
          isFalse,
          reason: 'Snapshot1 should not be in storage after deletion',
        );
        expect(
          snapshotStorage.getSnapshot(snapshot1.id),
          isNull,
          reason: 'getSnapshot() should return null for deleted snapshot',
        );

        // Verify snapshot2 still exists
        expect(
          snapshotStorage.containsSnapshot(snapshot2.id),
          isTrue,
          reason:
              'Snapshot2 should still be in storage after snapshot1 deletion',
        );
        expect(
          snapshotStorage.getSnapshot(snapshot2.id),
          isNotNull,
          reason: 'getSnapshot() should return snapshot2',
        );

        // Verify the remaining snapshot is the correct one
        final remainingSnapshots = snapshotStorage.getSnapshots();
        expect(
          remainingSnapshots.first.id,
          equals(snapshot2.id),
          reason: 'The remaining snapshot should be snapshot2',
        );
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

    group('CRDTDocumentStorage', () {
      test('CRDTDocumentStorage constructor holds storages', () async {
        const documentId = 'doc-store-ctor';
        final changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);
        final snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        final docStorage = CRDTDocumentStorage(
          changes: changeStorage,
          snapshots: snapshotStorage,
        );

        expect(docStorage.changes, isA<CRDTChangeStorage>());
        expect(docStorage.snapshots, isA<CRDTSnapshotStorage>());
      });

      test('openStorageForDocument opens both storages', () async {
        const documentId = 'doc-open-both';
        final storage = await CRDTHive.openStorageForDocument(documentId);

        expect(storage.changes, isA<CRDTChangeStorage>());
        expect(storage.snapshots, isA<CRDTSnapshotStorage>());

        // Write something and verify persistence across reopen
        final id =
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1));
        final change = Change.fromPayload(
          id: id,
          deps: {},
          author: id.peerId,
          payload: {'x': 1},
        );
        await storage.changes.saveChange(change);

        final snap = Snapshot(
          id: 'snap-1',
          versionVector: VersionVector({id.peerId: id.hlc}),
          data: {'k': 'v'},
        );
        await storage.snapshots.saveSnapshot(snap);

        await CRDTHive.closeAllBoxes();

        final reopened = await CRDTHive.openStorageForDocument(documentId);
        expect(reopened.changes.getChanges(), isNotEmpty);
        expect(reopened.snapshots.getSnapshots(), isNotEmpty);
      });

      test('deleteBox removes arbitrary box from disk', () async {
        const boxName = 'temp_box_for_delete';
        final box = await Hive.openBox<String>(boxName);
        await box.put('k', 'v');
        await box.close();

        await CRDTHive.deleteBox(boxName);

        // Reopen: it should be a new empty box
        final reopened = await Hive.openBox<String>(boxName);
        expect(reopened.length, 0);
        await reopened.close();
      });

      test('deleteDocumentData removes both changes_ and snapshots_ boxes',
          () async {
        const documentId = 'doc-del-data';
        // Open and write into document-scoped boxes
        final changes = await CRDTHive.openChangeStorageForDocument(documentId);
        final snapshots =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        final id =
            OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));
        final change = Change.fromPayload(
          id: id,
          deps: {},
          author: id.peerId,
          payload: {'p': true},
        );
        await changes.saveChange(change);
        await snapshots.saveSnapshot(
          Snapshot(
            id: 's-del',
            versionVector: VersionVector({id.peerId: id.hlc}),
            data: {'d': 1},
          ),
        );

        await CRDTHive.closeAllBoxes();

        await CRDTHive.deleteDocumentData(documentId);

        // Reopen storages for same document: they should be empty
        final reopenedChanges =
            await CRDTHive.openChangeStorageForDocument(documentId);
        final reopenedSnapshots =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(reopenedChanges.count, 0);
        expect(reopenedSnapshots.count, 0);
      });
    });

    test('SnapshotAdapter (data adapter mode): roundtrip complex data',
        () async {
      const documentId = 'doc-data-snap-roundtrip';
      final storage = await CRDTHive.openSnapshotStorageForDocument(documentId);

      final author = PeerId.generate();
      final vv = VersionVector({author: HybridLogicalClock(l: 777, c: 3)});
      final data = <String, dynamic>{
        'title': 'with-adapter',
        'meta': {
          'tags': ['x', 'y'],
          'flags': {'draft': true},
        },
        'count': 7,
      };

      final snapshot = Snapshot(id: 'snap-data', versionVector: vv, data: data);
      await storage.saveSnapshot(snapshot);

      await CRDTHive.closeAllBoxes();

      final reopened =
          await CRDTHive.openSnapshotStorageForDocument(documentId);
      final loaded = reopened.getSnapshot('snap-data');

      expect(loaded, isNotNull);
      expect(loaded!.id, equals('snap-data'));
      expect(loaded.versionVector.entries.length, equals(1));
      expect(loaded.data, equals(data));
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
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ObjectValue &&
        other.height == height &&
        other.width == width &&
        other.offsetX == offsetX &&
        other.offsetY == offsetY;
  }

  @override
  int get hashCode => Object.hash(height, width, offsetX, offsetY);

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
