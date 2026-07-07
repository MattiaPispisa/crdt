import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import 'helpers/hive_test_path.dart';

void main() {
  group('CRDTHive', () {
    late String tempDir;

    setUpAll(() async {
      CRDTHive.initialize();
    });

    setUp(() async {
      tempDir = await hiveTestPath();
      Hive.init(tempDir);
    });

    tearDown(() async {
      await CRDTHive.closeAllBoxes();
      await Hive.deleteFromDisk();
    });

    test('ChangeAdapter: round-trips binary payload bytes', () async {
      const documentId = 'doc-json-1';
      final storage = await CRDTHive.openChangeStorageForDocument(documentId);

      final id = OperationId(
        PeerId.generate(),
        HybridLogicalClock(l: 123, c: 4),
      );

      // Arbitrary opaque payload — Hive must preserve it byte-for-byte.
      final payloadBytes = Uint8List.fromList([1, 2, 3, 4, 5, 250, 251]);

      final change = Change.fromPayloadBytes(
        id: id,
        deps: {},
        author: id.peerId,
        payloadBytes: payloadBytes,
      );

      await storage.saveChange(change);

      await CRDTHive.closeAllBoxes();
      final reopened = await CRDTHive.openChangeStorageForDocument(documentId);

      final changes = reopened.getChanges();

      expect(changes.length, equals(1));
      expect(changes.first.payloadBytes(), equals(payloadBytes));
      expect(reopened.isEmpty, isFalse);
      expect(reopened.isNotEmpty, isTrue);
      expect(changes.first.id, equals(id));
      expect(changes.first.author, equals(id.peerId));
    });

    test('CRDTChangeStorage deleteChanges and clear', () async {
      const documentId = 'doc-json-2';
      final storage = await CRDTHive.openChangeStorageForDocument(documentId);

      Change makeChange(int l, int c) {
        final id = OperationId(
          PeerId.generate(),
          HybridLogicalClock(l: l, c: c),
        );
        return Change.fromPayloadBytes(
          id: id,
          deps: {},
          author: id.peerId,
          payloadBytes: Uint8List.fromList(utf8.encode('$l.$c')),
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

    test('SnapshotAdapter and CRDTSnapshotStorage ops', () async {
      const documentId = 'doc-snap-3';
      final storage = await CRDTHive.openSnapshotStorageForDocument(documentId);

      Snapshot makeSnapshot(int l, int c, Map<String, Uint8List> data) {
        return Snapshot(
          id: 's_${l}_$c',
          versionVector: VersionVector(
            {PeerId.generate(): HybridLogicalClock(l: l, c: c)},
          ),
          data: data,
        );
      }

      final s1 = makeSnapshot(1, 1, {
        'a': Uint8List.fromList([1]),
      });
      final s2 = makeSnapshot(1, 2, {
        'b': Uint8List.fromList([0]),
      });
      final s3 = makeSnapshot(2, 1, {
        'list': Uint8List.fromList([1, 2]),
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

    test('SnapshotAdapter: roundtrip opaque binary blobs', () async {
      const documentId = 'doc-snap-roundtrip';
      final storage = await CRDTHive.openSnapshotStorageForDocument(documentId);

      final author = PeerId.generate();
      final vv = VersionVector({author: HybridLogicalClock(l: 999, c: 2)});
      final data = <String, Uint8List>{
        'title': Uint8List.fromList(utf8.encode('doc')),
        'count': Uint8List.fromList([42, 0, 0, 0]),
        'blob': Uint8List.fromList(List<int>.generate(32, (i) => i)),
      };

      final snapshot = Snapshot(id: 'snap', versionVector: vv, data: data);
      await storage.saveSnapshot(snapshot);

      await CRDTHive.closeAllBoxes();

      final reopened =
          await CRDTHive.openSnapshotStorageForDocument(documentId);
      final loaded = reopened.getSnapshot('snap');

      expect(loaded, isNotNull);
      expect(loaded!.id, equals('snap'));
      expect(loaded.versionVector.entries.length, equals(1));
      expect(loaded.data.keys.toSet(), equals(data.keys.toSet()));
      for (final key in data.keys) {
        expect(loaded.data[key], equals(data[key]));
      }
    });

    group('Storage delete/contains single-item operations', () {
      test('CRDTChangeStorage.deleteChange returns true then false', () async {
        const documentId = 'doc-delete-change';
        final storage = await CRDTHive.openChangeStorageForDocument(documentId);

        final id =
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1));
        final change = Change.fromPayloadBytes(
          id: id,
          deps: {},
          author: id.peerId,
          payloadBytes: Uint8List.fromList(const [1, 2, 3]),
        );

        await storage.saveChange(change);
        expect(storage.count, equals(1));

        // First delete: present → true.
        expect(await storage.deleteChange(change), isTrue);
        expect(storage.count, isZero);

        // Second delete: absent → false (covers the `else` branch).
        expect(await storage.deleteChange(change), isFalse);
      });

      test('CRDTSnapshotStorage.deleteSnapshot returns true then false',
          () async {
        const documentId = 'doc-delete-snapshot';
        final storage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        final author = PeerId.generate();
        final snapshot = Snapshot(
          id: 'snap-1',
          versionVector: VersionVector(
            {author: HybridLogicalClock(l: 1, c: 1)},
          ),
          data: {
            'k': Uint8List.fromList([1]),
          },
        );

        await storage.saveSnapshot(snapshot);
        expect(storage.count, equals(1));

        expect(await storage.deleteSnapshot('snap-1'), isTrue);
        expect(storage.count, isZero);

        expect(await storage.deleteSnapshot('snap-1'), isFalse);
      });

      test('CRDTSnapshotStorage.containsSnapshot reflects presence', () async {
        const documentId = 'doc-contains-snapshot';
        final storage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(storage.containsSnapshot('absent'), isFalse);

        final author = PeerId.generate();
        await storage.saveSnapshot(
          Snapshot(
            id: 'present',
            versionVector:
                VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
            data: {
              'k': Uint8List.fromList([1]),
            },
          ),
        );
        expect(storage.containsSnapshot('present'), isTrue);
      });
    });

    group('Complex value types', () {
      test(
          'CRDTListHandler<ObjectValue> with binary codec round-trips '
          'changes through Hive', () async {
        const documentId = 'doc-complex-value';
        var changeStorage =
            await CRDTHive.openChangeStorageForDocument(documentId);

        final document = CRDTDocument(peerId: PeerId.generate());
        final list = CRDTListHandler<ObjectValue>(
          document,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        );

        const v1 = ObjectValue(
          height: 10,
          width: 20,
          offsetX: 1.5,
          offsetY: 2.5,
        );
        const v2 = ObjectValue(
          height: 30,
          width: 40,
          offsetX: 3.5,
          offsetY: 4.5,
        );

        list
          ..insert(0, v1)
          ..insert(1, v2);

        await changeStorage.saveChanges(document.exportChanges());
        await CRDTHive.closeAllBoxes();

        changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(changeStorage.getChanges());
        final newList = CRDTListHandler<ObjectValue>(
          newDocument,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        );

        expect(newList.value, equals([v1, v2]));
      });

      test(
          'CRDTListHandler<ObjectValue> snapshot round-trips through Hive '
          'using the handler-owned binary state', () async {
        const documentId = 'doc-complex-snapshot';
        final storage =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        final document = CRDTDocument(peerId: PeerId.generate());
        final list = CRDTListHandler<ObjectValue>(
          document,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        );

        const v1 = ObjectValue(
          height: 10,
          width: 20,
          offsetX: 1.5,
          offsetY: 2.5,
        );
        const v2 = ObjectValue(
          height: 30,
          width: 40,
          offsetX: 3.5,
          offsetY: 4.5,
        );
        list
          ..insert(0, v1)
          ..insert(1, v2);

        final snapshot = document.takeSnapshot(pruneHistory: false);
        await storage.saveSnapshot(snapshot);
        await CRDTHive.closeAllBoxes();

        final reopened =
            await CRDTHive.openSnapshotStorageForDocument(documentId);
        final loaded = reopened.getSnapshot(snapshot.id);
        expect(loaded, isNotNull);

        // Restore the snapshot into a fresh document and rebuild the
        // handler — it should expose the original typed values.
        final restoredDoc = CRDTDocument(peerId: PeerId.generate())
          ..mergeSnapshot(loaded!, pruneHistory: false);
        final restoredList = CRDTListHandler<ObjectValue>(
          restoredDoc,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        );
        expect(restoredList.value, equals([v1, v2]));
      });
    });

    group('Multiple documents', () {
      test('should handle multiple documents independently', () async {
        final document1 = CRDTDocument(
          peerId: PeerId.parse('5fe9139e-6c1d-4a6b-a767-4071b1e379dd'),
        );
        final document2 = CRDTDocument(
          peerId: PeerId.parse('32f8d819-8b64-4cf2-a239-e2e6414b19ef'),
        );
        final changes1 = <Change>[];
        final changes2 = <Change>[];
        document1.localChanges.listen(changes1.add);
        document2.localChanges.listen(changes2.add);

        CRDTListHandler<String>(document1, 'list')
          ..insert(0, 'a')
          ..insert(1, 'b');
        CRDTListHandler<String>(document2, 'list')
          ..insert(0, 'c')
          ..insert(1, 'd');

        await Future<void>.delayed(Duration.zero);

        var storage1 = await CRDTHive.openChangeStorageForDocument(
          document1.peerId.toString(),
        );
        var storage2 = await CRDTHive.openChangeStorageForDocument(
          document2.peerId.toString(),
        );
        await storage1.saveChanges(changes1);
        await storage2.saveChanges(changes2);

        expect(storage1.count, equals(2));
        expect(storage2.count, equals(2));

        await CRDTHive.closeAllBoxes();

        storage1 = await CRDTHive.openChangeStorageForDocument(
          document1.peerId.toString(),
        );
        storage2 = await CRDTHive.openChangeStorageForDocument(
          document2.peerId.toString(),
        );

        final reopened1 = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(storage1.getChanges());
        final reopened2 = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(storage2.getChanges());

        expect(
          CRDTListHandler<String>(reopened1, 'list').value,
          equals(['a', 'b']),
        );
        expect(
          CRDTListHandler<String>(reopened2, 'list').value,
          equals(['c', 'd']),
        );
      });
    });

    group('CRDTDocumentStorage', () {
      test('constructor holds both storages', () async {
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

      test('openStorageForDocument opens both storages and persists', () async {
        const documentId = 'doc-open-both';
        final storage = await CRDTHive.openStorageForDocument(documentId);

        expect(storage.changes, isA<CRDTChangeStorage>());
        expect(storage.snapshots, isA<CRDTSnapshotStorage>());

        final id =
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1));
        final change = Change.fromPayloadBytes(
          id: id,
          deps: {},
          author: id.peerId,
          payloadBytes: Uint8List.fromList(const [1, 2, 3]),
        );
        await storage.changes.saveChange(change);

        final snap = Snapshot(
          id: 'snap-1',
          versionVector: VersionVector({id.peerId: id.hlc}),
          data: {
            'k': Uint8List.fromList([1]),
          },
        );
        await storage.snapshots.saveSnapshot(snap);

        await CRDTHive.closeAllBoxes();

        final reopened = await CRDTHive.openStorageForDocument(documentId);
        expect(reopened.changes.getChanges(), isNotEmpty);
        expect(reopened.snapshots.getSnapshots(), isNotEmpty);
      });

      test('deleteBox removes an arbitrary box from disk', () async {
        const boxName = 'temp_box_for_delete';
        final box = await Hive.openBox<String>(boxName);
        await box.put('k', 'v');
        await box.close();

        await CRDTHive.deleteBox(boxName);

        final reopened = await Hive.openBox<String>(boxName);
        expect(reopened.length, 0);
        await reopened.close();
      });

      test('deleteDocumentData removes both changes_ and snapshots_ boxes',
          () async {
        const documentId = 'doc-del-data';
        final changes = await CRDTHive.openChangeStorageForDocument(documentId);
        final snapshots =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        final id =
            OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));
        await changes.saveChange(
          Change.fromPayloadBytes(
            id: id,
            deps: {},
            author: id.peerId,
            payloadBytes: Uint8List.fromList(const [9, 8, 7]),
          ),
        );
        await snapshots.saveSnapshot(
          Snapshot(
            id: 's-del',
            versionVector: VersionVector({id.peerId: id.hlc}),
            data: {
              'd': Uint8List.fromList([1]),
            },
          ),
        );

        await CRDTHive.closeAllBoxes();
        await CRDTHive.deleteDocumentData(documentId);

        final reopenedChanges =
            await CRDTHive.openChangeStorageForDocument(documentId);
        final reopenedSnapshots =
            await CRDTHive.openSnapshotStorageForDocument(documentId);

        expect(reopenedChanges.count, 0);
        expect(reopenedSnapshots.count, 0);
      });
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

      // Unique document id per test: these tests reuse the same document id,
      // which collides on the web where Hive boxes live in a per-origin
      // IndexedDB (the `Hive.init` path is ignored) rather than an isolated
      // temp directory as on the VM.
      var testIndex = 0;

      setUp(() {
        changesToSave = [];
        documentId = 'doc-all-handlers-${testIndex++}';
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

      test('should handle complex operations across multiple handlers',
          () async {
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
}

class ObjectValueCodec implements ValueCodec<ObjectValue> {
  const ObjectValueCodec();

  @override
  Uint8List encode(ObjectValue value) {
    final out = ByteData(32)
      ..setFloat64(0, value.height)
      ..setFloat64(8, value.width)
      ..setFloat64(16, value.offsetX)
      ..setFloat64(24, value.offsetY);
    return out.buffer.asUint8List();
  }

  @override
  ObjectValue decode(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    return ObjectValue(
      height: view.getFloat64(0),
      width: view.getFloat64(8),
      offsetX: view.getFloat64(16),
      offsetY: view.getFloat64(24),
    );
  }
}
