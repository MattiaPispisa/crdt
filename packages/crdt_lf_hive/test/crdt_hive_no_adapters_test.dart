import 'dart:io';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTHive without data adapter', () {
    late String tempDir;

    setUpAll(() async {
      // Initialize adapters with JSON mode for payload/data
      CRDTHive.initialize();
    });

    setUp(() async {
      final directory =
          await Directory.systemTemp.createTemp('crdt_hive_json_adapter_test');
      tempDir = directory.path;
      Hive.init(tempDir);
    });

    tearDown(() async {
      await CRDTHive.closeAllBoxes();
      await Hive.deleteFromDisk();
    });

    test('ChangeAdapter JSON mode: roundtrip complex payload', () async {
      // Test JSON serialization with complex nested payloads
      const documentId = 'doc-json-1';
      final storage = await CRDTHive.openChangeStorageForDocument(documentId);

      // Create an operation ID with specific clock values
      final id = OperationId(
        PeerId.generate(),
        HybridLogicalClock(l: 123, c: 4),
      );

      // Create a complex payload with nested structures
      final payload = <String, dynamic>{
        'k1': 'v1',
        'nested': {'a': 1, 'b': true},
        'list': [1, 2, 3],
      };

      // Create a change with the complex payload
      final change = Change.fromPayload(
        id: id,
        deps: {},
        author: id.peerId,
        payload: payload,
      );

      // Save the change using JSON serialization
      await storage.saveChange(change);

      // Close and reopen storage to test persistence
      await CRDTHive.closeAllBoxes();
      final reopened = await CRDTHive.openChangeStorageForDocument(documentId);

      // Retrieve all changes from storage
      final changes = reopened.getChanges();

      // Verify the change was saved and loaded correctly
      expect(
        changes.length,
        equals(1),
        reason: 'Should have exactly one change after reopening',
      );
      expect(
        changes.first.payload,
        equals(payload),
        reason: 'Payload should be deserialized identically via JSON',
      );
      expect(
        changes.first.payload['k1'],
        equals('v1'),
        reason: 'Top-level string values should be preserved',
      );
      expect(
        changes.first.payload['nested'],
        equals({'a': 1, 'b': true}),
        reason: 'Nested maps should be preserved',
      );
      expect(
        changes.first.payload['list'],
        equals([1, 2, 3]),
        reason: 'Lists should be preserved',
      );
      expect(
        reopened.isEmpty,
        isFalse,
        reason: 'Storage should not be empty after loading',
      );
      expect(
        reopened.isNotEmpty,
        isTrue,
        reason: 'isNotEmpty should return true',
      );
      expect(
        changes.first.id,
        equals(id),
        reason: 'Change ID should be preserved',
      );
      expect(
        changes.first.author,
        equals(id.peerId),
        reason: 'Author should be preserved',
      );
    });

    test('CRDTChangeStorage deleteChanges and clear', () async {
      const documentId = 'doc-json-2';
      final storage = await CRDTHive.openChangeStorageForDocument(documentId);

      Change makeChange(int l, int c) {
        final id = OperationId(
          PeerId.generate(),
          HybridLogicalClock(l: l, c: c),
        );
        return Change.fromPayload(
          id: id,
          deps: {},
          author: id.peerId,
          payload: {'value': '$l.$c'},
        );
      }

      final c1 = makeChange(1, 1);
      final c2 = makeChange(1, 2);
      final c3 = makeChange(2, 1);

      await storage.saveChanges([c1, c2, c3]);
      expect(storage.count, 3);
      expect(storage.isEmpty, isFalse);
      expect(storage.isNotEmpty, isTrue);

      final deleted = await storage.deleteChanges([c1, c3]);
      expect(deleted, 2);
      expect(storage.count, 1);

      await storage.clear();
      expect(storage.count, 0);
      expect(storage.getChanges(), isEmpty);
      expect(storage.isEmpty, isTrue);
      expect(storage.isNotEmpty, isFalse);
    });

    test('SnapshotAdapter JSON mode and CRDTSnapshotStorage ops', () async {
      const documentId = 'doc-json-3';
      final storage = await CRDTHive.openSnapshotStorageForDocument(documentId);

      Snapshot makeSnapshot(int l, int c, Map<String, dynamic> data) {
        return Snapshot(
          id: 's_${l}_$c',
          versionVector: VersionVector(
            {PeerId.generate(): HybridLogicalClock(l: l, c: c)},
          ),
          data: data,
        );
      }

      final s1 = makeSnapshot(1, 1, {'a': 1});
      final s2 = makeSnapshot(1, 2, {'b': true});
      final s3 = makeSnapshot(2, 1, {
        'list': [1, 2],
      });

      await storage.saveSnapshots([s1, s2, s3]);
      expect(storage.count, 3);
      expect(storage.isEmpty, isFalse);
      expect(storage.isNotEmpty, isTrue);

      final deleted = await storage.deleteSnapshots([s1.id, s3.id]);
      expect(deleted, 2);
      expect(storage.count, 1);

      await storage.clear();
      expect(storage.count, 0);
      expect(storage.getSnapshots(), isEmpty);
      expect(storage.isEmpty, isTrue);
      expect(storage.isNotEmpty, isFalse);
    });

    test('SnapshotAdapter JSON mode: roundtrip complex data', () async {
      const documentId = 'doc-json-snap-roundtrip';
      final storage = await CRDTHive.openSnapshotStorageForDocument(documentId);

      final author = PeerId.generate();
      final vv = VersionVector({author: HybridLogicalClock(l: 999, c: 2)});
      final data = <String, dynamic>{
        'title': 'doc',
        'meta': {
          'tags': ['a', 'b'],
          'flags': {'public': true, 'archived': false},
        },
        'count': 42,
      };

      final snapshot = Snapshot(id: 'snap-json', versionVector: vv, data: data);
      await storage.saveSnapshot(snapshot);

      await CRDTHive.closeAllBoxes();

      final reopened =
          await CRDTHive.openSnapshotStorageForDocument(documentId);
      final loaded = reopened.getSnapshot('snap-json');

      expect(loaded, isNotNull);
      expect(loaded!.id, equals('snap-json'));
      expect(loaded.versionVector.entries.length, equals(1));
      expect(loaded.data, equals(data));
    });

    group('All handlers with JSON mode', () {
      late List<Change> changesToSave;
      late String documentId;
      late CRDTDocument document;

      late CRDTListHandler<String> list;
      late CRDTMapHandler<int> map;
      late CRDTTextHandler text;
      late CRDTFugueTextHandler fugueText;
      late CRDTORSetHandler<String> orSet;
      late CRDTORMapHandler<String, int> orMap;

      setUp(() {
        changesToSave = [];
        documentId = 'doc-all-handlers';
        document = CRDTDocument(peerId: PeerId.generate())
          ..localChanges.listen(changesToSave.add);

        list = CRDTListHandler<String>(document, 'list');
        map = CRDTMapHandler<int>(document, 'map');
        text = CRDTTextHandler(document, 'text');
        fugueText = CRDTFugueTextHandler(document, 'fugueText');
        orSet = CRDTORSetHandler(document, 'orSet');
        orMap = CRDTORMapHandler(document, 'orMap');
      });

      test('should save and load changes for all handlers', () async {
        // Test JSON serialization with all handler types using primitive types
        var changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        expect(
          changeStorage.count,
          equals(0),
          reason: 'Storage should be empty initially',
        );

        // Create changes for CRDTListHandler with String values
        list
          ..insert(0, 'first')
          ..insert(1, 'second');

        // Create changes for CRDTMapHandler with int values
        map
          ..set('count', 42)
          ..set('total', 100);

        // Create changes for CRDTTextHandler
        text.insert(0, 'Hello World');

        // Create changes for CRDTFugueTextHandler
        fugueText.insert(0, 'Fugue Text');

        // Create changes for CRDTORSetHandler
        orSet
          ..add('alpha')
          ..add('beta');

        // Create changes for CRDTORMapHandler
        orMap
          ..put('x', 10)
          ..put('y', 20);

        // Wait for local changes stream to emit all changes
        await Future<void>.delayed(Duration.zero);

        // Verify all changes were captured
        expect(
          changesToSave,
          isNotEmpty,
          reason: 'Changes should have been captured from all handlers',
        );
        expect(
          changesToSave.length,
          greaterThan(5),
          reason: 'Should have multiple changes from 6 different handlers',
        );

        // Save all changes using JSON serialization
        await changeStorage.saveChanges(changesToSave);

        // Close and reopen storage to verify JSON persistence
        await CRDTHive.closeAllBoxes();
        changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);

        // Verify changes were persisted via JSON
        expect(
          changeStorage.count,
          greaterThan(0),
          reason: 'Storage should contain saved changes after reopening',
        );
        expect(
          changeStorage.count,
          equals(changesToSave.length),
          reason: 'All changes should be persisted',
        );

        // Import changes into new document to verify deserialization
        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage.getChanges());

        // Verify CRDTListHandler data was correctly deserialized from JSON
        final newList = CRDTListHandler<String>(newDocument, 'list');
        expect(
          newList.length,
          equals(2),
          reason: 'List should contain 2 items',
        );
        expect(
          newList[0],
          equals('first'),
          reason: 'First list item should be "first"',
        );
        expect(
          newList[1],
          equals('second'),
          reason: 'Second list item should be "second"',
        );

        // Verify CRDTMapHandler data was correctly deserialized from JSON
        final newMap = CRDTMapHandler<int>(newDocument, 'map');
        expect(
          newMap.value,
          equals({'count': 42, 'total': 100}),
          reason: 'Map should contain both key-value pairs',
        );
        expect(
          newMap['count'],
          equals(42),
          reason: 'Map count value should be 42',
        );
        expect(
          newMap['total'],
          equals(100),
          reason: 'Map total value should be 100',
        );

        // Verify CRDTTextHandler data was correctly deserialized from JSON
        final newText = CRDTTextHandler(newDocument, 'text');
        expect(
          newText.value,
          equals('Hello World'),
          reason: 'Text should be "Hello World"',
        );
        expect(
          newText.length,
          equals(11),
          reason: 'Text length should be 11',
        );

        // Verify CRDTFugueTextHandler data was correctly deserialized from JSON
        final newFugueText = CRDTFugueTextHandler(newDocument, 'fugueText');
        expect(
          newFugueText.value,
          equals('Fugue Text'),
          reason: 'FugueText should be "Fugue Text"',
        );
        expect(
          newFugueText.length,
          equals(10),
          reason: 'FugueText length should be 10',
        );

        // Verify CRDTORSetHandler data (Set serialized as List in JSON)
        final newOrSet = CRDTORSetHandler<String>(newDocument, 'orSet');
        expect(
          newOrSet.value,
          equals({'alpha', 'beta'}),
          reason: 'ORSet should contain both elements',
        );
        expect(
          newOrSet.value.contains('alpha'),
          isTrue,
          reason: 'ORSet should contain "alpha"',
        );
        expect(
          newOrSet.value.contains('beta'),
          isTrue,
          reason: 'ORSet should contain "beta"',
        );

        // Verify CRDTORMapHandler data was correctly deserialized from JSON
        final newOrMap = CRDTORMapHandler<String, int>(newDocument, 'orMap');
        expect(
          newOrMap.value,
          equals({'x': 10, 'y': 20}),
          reason: 'ORMap should contain both entries',
        );
        expect(
          newOrMap['x'],
          equals(10),
          reason: 'ORMap x value should be 10',
        );
        expect(
          newOrMap['y'],
          equals(20),
          reason: 'ORMap y value should be 20',
        );
      });

      test('should save and load snapshots for all handlers', () async {
        var snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(snapshotStorage.count, isZero);

        // Create data for all handlers
        list
          ..insert(0, 'a')
          ..insert(1, 'b');

        final snapshot1 = document.takeSnapshot();

        map
          ..set('key1', 10)
          ..set('key2', 20);

        orSet
          ..add('set1')
          ..add('set2');

        orMap
          ..put('k1', 1)
          ..put('k2', 2);

        final snapshot2 = document.takeSnapshot();

        text.insert(0, 'Text content');
        fugueText.insert(0, 'Fugue content');

        final snapshot3 = document.takeSnapshot();

        await snapshotStorage.saveSnapshots([snapshot1, snapshot2, snapshot3]);

        await CRDTHive.closeAllBoxes();

        snapshotStorage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(snapshotStorage.count, equals(3));

        // Import last snapshot (snapshot3) which has all data
        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importSnapshot(snapshot3);

        final newList = CRDTListHandler<String>(newDocument, 'list');
        expect(newList.length, 2);
        expect(newList[0], 'a');
        expect(newList[1], 'b');

        final newMap = CRDTMapHandler<int>(newDocument, 'map');
        expect(newMap.value, {'key1': 10, 'key2': 20});

        final newText = CRDTTextHandler(newDocument, 'text');
        expect(newText.value, 'Text content');

        final newFugueText = CRDTFugueTextHandler(newDocument, 'fugueText');
        expect(newFugueText.value, 'Fugue content');

        final newOrSet = CRDTORSetHandler<String>(newDocument, 'orSet');
        expect(newOrSet.value, {'set1', 'set2'});

        final newOrMap = CRDTORMapHandler<String, int>(newDocument, 'orMap');
        expect(newOrMap.value, {'k1': 1, 'k2': 2});
      });

      test('should handle complex operations across multiple handlers', () async {
        var changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        // Perform multiple operations on each handler
        list
          ..insert(0, 'item1')
          ..insert(1, 'item2')
          ..delete(0, 1);

        map
          ..set('a', 1)
          ..set('b', 2)
          ..delete('a');

        text
          ..insert(0, 'Hello')
          ..insert(5, ' World')
          ..delete(0, 6);

        fugueText
          ..insert(0, 'Test')
          ..insert(4, ' Text')
          ..delete(0, 5);

        orSet
          ..add('x')
          ..add('y')
          ..remove('x');

        orMap
          ..put('m', 100)
          ..put('n', 200)
          ..remove('m');

        await Future<void>.delayed(Duration.zero);

        await changeStorage.saveChanges(changesToSave);

        await CRDTHive.closeAllBoxes();

        changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage.getChanges());

        final newList = CRDTListHandler<String>(newDocument, 'list');
        expect(newList.length, 1);
        expect(newList[0], 'item2');

        final newMap = CRDTMapHandler<int>(newDocument, 'map');
        expect(newMap.value, {'b': 2});

        final newText = CRDTTextHandler(newDocument, 'text');
        expect(newText.value, 'World');

        final newFugueText = CRDTFugueTextHandler(newDocument, 'fugueText');
        expect(newFugueText.value, 'Text');

        final newOrSet = CRDTORSetHandler<String>(newDocument, 'orSet');
        expect(newOrSet.value, {'y'});

        final newOrMap = CRDTORMapHandler<String, int>(newDocument, 'orMap');
        expect(newOrMap.value, {'n': 200});
      });
    });
  });
}
