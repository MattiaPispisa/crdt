@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';
import 'package:drift/native.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTDrift', () {
    late Directory tempDir;
    late String dbPath;
    late CRDTDrift storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('crdt_drift_test');
      dbPath = '${tempDir.path}/crdt.db';
      storage = CRDTDrift.open(File(dbPath));
    });

    tearDown(() async {
      await storage.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

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

    test('round-trips binary payload bytes across reopen', () async {
      const documentId = 'doc-1';
      final changeStorage = storage.changeStorageForDocument(documentId);

      final id = OperationId(
        PeerId.generate(),
        HybridLogicalClock(l: 123, c: 4),
      );
      final payloadBytes = Uint8List.fromList([1, 2, 3, 4, 5, 250, 251]);
      final change = Change.fromPayloadBytes(
        id: id,
        deps: {},
        author: id.peerId,
        payloadBytes: payloadBytes,
      );

      await changeStorage.saveChange(change);

      await storage.close();
      storage = CRDTDrift.open(File(dbPath));
      final reopened = storage.changeStorageForDocument(documentId);

      final changes = await reopened.getChanges();
      expect(changes.length, equals(1));
      expect(changes.first.payloadBytes(), equals(payloadBytes));
      expect(changes.first.id, equals(id));
      expect(changes.first.author, equals(id.peerId));
      expect(await reopened.isEmpty, isFalse);
      expect(await reopened.isNotEmpty, isTrue);
    });

    test('saveChanges/deleteChanges/clear and empty-list branches', () async {
      const documentId = 'doc-2';
      final changeStorage = storage.changeStorageForDocument(documentId);

      await changeStorage.saveChanges([]);
      expect(await changeStorage.deleteChanges([]), isZero);
      expect(await changeStorage.count, isZero);

      final c1 = makeChange(1, 1);
      final c2 = makeChange(1, 2);
      final c3 = makeChange(2, 1);

      await changeStorage.saveChanges([c1, c2, c3]);
      expect(await changeStorage.count, 3);
      expect(await changeStorage.isEmpty, isFalse);
      expect(await changeStorage.isNotEmpty, isTrue);

      expect(await changeStorage.deleteChanges([c1, c3]), 2);
      expect(await changeStorage.count, 1);

      await changeStorage.clear();
      expect(await changeStorage.count, 0);
      expect(await changeStorage.getChanges(), isEmpty);
      expect(await changeStorage.isEmpty, isTrue);
      expect(await changeStorage.isNotEmpty, isFalse);
    });

    test('deleteChange returns true then false', () async {
      const documentId = 'doc-del-change';
      final changeStorage = storage.changeStorageForDocument(documentId);

      final change = makeChange(1, 1);
      await changeStorage.saveChange(change);
      expect(await changeStorage.count, 1);

      expect(await changeStorage.deleteChange(change), isTrue);
      expect(await changeStorage.count, isZero);
      expect(await changeStorage.deleteChange(change), isFalse);
    });

    test('snapshot ops: save/delete/clear and empty-list branches', () async {
      const documentId = 'doc-snap';
      final snapshotStorage = storage.snapshotStorageForDocument(documentId);

      Snapshot makeSnapshot(int l, int c, Map<String, Uint8List> data) {
        return Snapshot(
          id: 's_${l}_$c',
          versionVector: VersionVector(
            {PeerId.generate(): HybridLogicalClock(l: l, c: c)},
          ),
          data: data,
        );
      }

      await snapshotStorage.saveSnapshots([]);
      expect(await snapshotStorage.deleteSnapshots([]), isZero);
      expect(await snapshotStorage.count, isZero);

      final s1 = makeSnapshot(1, 1, {
        'a': Uint8List.fromList([1]),
      });
      final s2 = makeSnapshot(1, 2, {
        'b': Uint8List.fromList([0]),
      });
      final s3 = makeSnapshot(2, 1, {
        'list': Uint8List.fromList([1, 2]),
      });

      await snapshotStorage.saveSnapshots([s1, s2, s3]);
      expect(await snapshotStorage.count, 3);
      expect(await snapshotStorage.isEmpty, isFalse);
      expect(await snapshotStorage.isNotEmpty, isTrue);

      expect(await snapshotStorage.deleteSnapshots([s1.id, s3.id]), 2);
      expect(await snapshotStorage.count, 1);

      await snapshotStorage.clear();
      expect(await snapshotStorage.count, 0);
      expect(await snapshotStorage.getSnapshots(), isEmpty);
      expect(await snapshotStorage.isEmpty, isTrue);
      expect(await snapshotStorage.isNotEmpty, isFalse);
    });

    test('snapshot round-trips opaque binary blobs across reopen', () async {
      const documentId = 'doc-snap-roundtrip';
      final snapshotStorage = storage.snapshotStorageForDocument(documentId);

      final author = PeerId.generate();
      final vv = VersionVector({author: HybridLogicalClock(l: 999, c: 2)});
      final data = <String, Uint8List>{
        'title': Uint8List.fromList(utf8.encode('doc')),
        'count': Uint8List.fromList([42, 0, 0, 0]),
        'blob': Uint8List.fromList(List<int>.generate(32, (i) => i)),
      };

      await snapshotStorage.saveSnapshot(
        Snapshot(id: 'snap', versionVector: vv, data: data),
      );

      await storage.close();
      storage = CRDTDrift.open(File(dbPath));
      final reopened = storage.snapshotStorageForDocument(documentId);

      final loaded = await reopened.getSnapshot('snap');
      expect(loaded, isNotNull);
      expect(loaded!.id, equals('snap'));
      expect(loaded.versionVector.entries.length, equals(1));
      expect(loaded.data.keys.toSet(), equals(data.keys.toSet()));
      for (final key in data.keys) {
        expect(loaded.data[key], equals(data[key]));
      }
      expect(await reopened.getSnapshot('absent'), isNull);
    });

    test('deleteSnapshot and containsSnapshot reflect presence', () async {
      const documentId = 'doc-contains';
      final snapshotStorage = storage.snapshotStorageForDocument(documentId);

      expect(await snapshotStorage.containsSnapshot('absent'), isFalse);
      expect(await snapshotStorage.deleteSnapshot('absent'), isFalse);

      final author = PeerId.generate();
      await snapshotStorage.saveSnapshot(
        Snapshot(
          id: 'present',
          versionVector: VersionVector(
            {author: HybridLogicalClock(l: 1, c: 1)},
          ),
          data: {
            'k': Uint8List.fromList([1]),
          },
        ),
      );
      expect(await snapshotStorage.containsSnapshot('present'), isTrue);
      expect(await snapshotStorage.deleteSnapshot('present'), isTrue);
      expect(await snapshotStorage.containsSnapshot('present'), isFalse);
    });

    test('memory() database works without a file', () async {
      final memory = CRDTDrift.memory();
      final changeStorage = memory.changeStorageForDocument('doc');
      final change = makeChange(1, 1);
      await changeStorage.saveChange(change);
      expect(await changeStorage.count, 1);
      expect((await changeStorage.getChanges()).first.id, equals(change.id));
      await memory.close();
    });

    test('fromDatabase wraps an existing database', () async {
      final database = CRDTDriftDatabase(NativeDatabase.memory());
      final wrapped = CRDTDrift.fromDatabase(database);
      await wrapped
          .changeStorageForDocument('doc')
          .saveChange(makeChange(1, 1));
      expect(await wrapped.changeStorageForDocument('doc').count, 1);
      await wrapped.close();
    });

    test('documents are isolated by document_id in a single database',
        () async {
      final s1 = storage.changeStorageForDocument('doc-a');
      final s2 = storage.changeStorageForDocument('doc-b');

      await s1.saveChanges([makeChange(1, 1), makeChange(1, 2)]);
      await s2.saveChange(makeChange(2, 1));

      expect(await s1.count, 2);
      expect(await s2.count, 1);

      await s1.clear();
      expect(await s1.count, 0);
      expect(await s2.count, 1, reason: 'clearing doc-a must not affect doc-b');
    });

    test('deleteDocumentData removes only the target document', () async {
      final a = storage.storageForDocument('doc-a');
      final b = storage.storageForDocument('doc-b');

      final id = OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));
      await a.changes.saveChange(
        Change.fromPayloadBytes(
          id: id,
          deps: {},
          author: id.peerId,
          payloadBytes: Uint8List.fromList(const [9, 8, 7]),
        ),
      );
      await a.snapshots.saveSnapshot(
        Snapshot(
          id: 's-del',
          versionVector: VersionVector({id.peerId: id.hlc}),
          data: {
            'd': Uint8List.fromList([1]),
          },
        ),
      );
      await b.changes.saveChange(makeChange(1, 1));

      await storage.deleteDocumentData('doc-a');

      expect(await a.changes.count, 0);
      expect(await a.snapshots.count, 0);
      expect(await b.changes.count, 1, reason: 'doc-b must be untouched');
    });

    group('CRDTDocumentStorage', () {
      test('storageForDocument opens both storages and persists', () async {
        const documentId = 'doc-open-both';
        final docStorage = storage.storageForDocument(documentId);

        expect(docStorage.documentId, documentId);
        expect(docStorage.changes, isA<CRDTDriftChangeStorage>());
        expect(docStorage.snapshots, isA<CRDTDriftSnapshotStorage>());

        final id = OperationId(
          PeerId.generate(),
          HybridLogicalClock(l: 1, c: 1),
        );
        await docStorage.changes.saveChange(
          Change.fromPayloadBytes(
            id: id,
            deps: {},
            author: id.peerId,
            payloadBytes: Uint8List.fromList(const [1, 2, 3]),
          ),
        );
        await docStorage.snapshots.saveSnapshot(
          Snapshot(
            id: 'snap-1',
            versionVector: VersionVector({id.peerId: id.hlc}),
            data: {
              'k': Uint8List.fromList([1]),
            },
          ),
        );

        await storage.close();
        storage = CRDTDrift.open(File(dbPath));
        final reopened = storage.storageForDocument(documentId);
        expect(await reopened.changes.getChanges(), isNotEmpty);
        expect(await reopened.snapshots.getSnapshots(), isNotEmpty);
      });

      test('constructor holds both storages', () {
        const documentId = 'doc-store-ctor';
        final docStorage = CRDTDocumentStorage(
          changes: storage.changeStorageForDocument(documentId),
          snapshots: storage.snapshotStorageForDocument(documentId),
        );
        expect(docStorage.changes, isA<CRDTDriftChangeStorage>());
        expect(docStorage.snapshots, isA<CRDTDriftSnapshotStorage>());
      });
    });

    group('Complex value types', () {
      const v1 = ObjectValue(height: 10, width: 20, offsetX: 1.5, offsetY: 2.5);
      const v2 = ObjectValue(height: 30, width: 40, offsetX: 3.5, offsetY: 4.5);

      test('CRDTListHandler<ObjectValue> round-trips changes', () async {
        const documentId = 'doc-complex-value';
        var changeStorage = storage.changeStorageForDocument(documentId);

        final document = CRDTDocument(peerId: PeerId.generate());
        CRDTListHandler<ObjectValue>(
          document,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        )
          ..insert(0, v1)
          ..insert(1, v2);

        await changeStorage.saveChanges(document.exportChanges());
        await storage.close();
        storage = CRDTDrift.open(File(dbPath));
        changeStorage = storage.changeStorageForDocument(documentId);

        final restored = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(await changeStorage.getChanges());
        final restoredList = CRDTListHandler<ObjectValue>(
          restored,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        );
        expect(restoredList.value, equals([v1, v2]));
      });

      test('CRDTListHandler<ObjectValue> round-trips snapshot state', () async {
        const documentId = 'doc-complex-snapshot';
        final snapshotStorage = storage.snapshotStorageForDocument(documentId);

        final document = CRDTDocument(peerId: PeerId.generate());
        CRDTListHandler<ObjectValue>(
          document,
          'shapes',
          valueCodec: const ObjectValueCodec(),
        )
          ..insert(0, v1)
          ..insert(1, v2);

        final snapshot = document.takeSnapshot(pruneHistory: false);
        await snapshotStorage.saveSnapshot(snapshot);
        await storage.close();
        storage = CRDTDrift.open(File(dbPath));

        final loaded = await storage
            .snapshotStorageForDocument(documentId)
            .getSnapshot(snapshot.id);
        expect(loaded, isNotNull);

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

    group('All handlers', () {
      late List<Change> changesToSave;
      late String documentId;
      late CRDTDocument document;
      late CRDTListHandler<String> list;
      late CRDTMapHandler<int> map;
      late CRDTTextHandler text;
      late CRDTFugueTextHandler fugueText;
      late CRDTORSetHandler<String> orSet;
      late CRDTORMapHandler<String, int> orMap;
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

      test('save and load changes for all handlers', () async {
        var changeStorage = storage.changeStorageForDocument(documentId);

        list
          ..insert(0, 'first')
          ..insert(1, 'second');
        map
          ..set('count', 42)
          ..set('total', 100);
        text.insert(0, 'Hello World');
        fugueText.insert(0, 'Fugue Text');
        orSet
          ..add('alpha')
          ..add('beta');
        orMap
          ..put('x', 10)
          ..put('y', 20);

        await Future<void>.delayed(Duration.zero);
        expect(changesToSave, isNotEmpty);

        await changeStorage.saveChanges(changesToSave);
        await storage.close();
        storage = CRDTDrift.open(File(dbPath));
        changeStorage = storage.changeStorageForDocument(documentId);
        expect(await changeStorage.count, equals(changesToSave.length));

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importChanges(await changeStorage.getChanges());

        expect(
          CRDTListHandler<String>(newDocument, 'list').value,
          equals(['first', 'second']),
        );
        expect(
          CRDTMapHandler<int>(newDocument, 'map').value,
          equals({'count': 42, 'total': 100}),
        );
        expect(
          CRDTTextHandler(newDocument, 'text').value,
          equals('Hello World'),
        );
        expect(
          CRDTFugueTextHandler(newDocument, 'fugueText').value,
          equals('Fugue Text'),
        );
        expect(
          CRDTORSetHandler<String>(newDocument, 'orSet').value,
          equals({'alpha', 'beta'}),
        );
        expect(
          CRDTORMapHandler<String, int>(newDocument, 'orMap').value,
          equals({'x': 10, 'y': 20}),
        );
      });

      test('save and load snapshots for all handlers', () async {
        final snapshotStorage = storage.snapshotStorageForDocument(documentId);

        list
          ..insert(0, 'a')
          ..insert(1, 'b');
        map
          ..set('key1', 10)
          ..set('key2', 20);
        orSet
          ..add('set1')
          ..add('set2');
        orMap
          ..put('k1', 1)
          ..put('k2', 2);
        text.insert(0, 'Text content');
        fugueText.insert(0, 'Fugue content');

        final snapshot = document.takeSnapshot();
        await snapshotStorage.saveSnapshots([snapshot]);
        await storage.close();
        storage = CRDTDrift.open(File(dbPath));

        final loaded = await storage
            .snapshotStorageForDocument(documentId)
            .getSnapshot(snapshot.id);
        expect(loaded, isNotNull);

        final newDocument = CRDTDocument(peerId: PeerId.generate())
          ..importSnapshot(loaded!);
        expect(
          CRDTListHandler<String>(newDocument, 'list').value,
          equals(['a', 'b']),
        );
        expect(
          CRDTMapHandler<int>(newDocument, 'map').value,
          equals({'key1': 10, 'key2': 20}),
        );
        expect(
          CRDTTextHandler(newDocument, 'text').value,
          equals('Text content'),
        );
        expect(
          CRDTFugueTextHandler(newDocument, 'fugueText').value,
          equals('Fugue content'),
        );
        expect(
          CRDTORSetHandler<String>(newDocument, 'orSet').value,
          equals({'set1', 'set2'}),
        );
        expect(
          CRDTORMapHandler<String, int>(newDocument, 'orMap').value,
          equals({'k1': 1, 'k2': 2}),
        );
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
