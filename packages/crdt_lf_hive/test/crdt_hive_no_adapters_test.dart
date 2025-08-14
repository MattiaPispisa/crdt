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
      const documentId = 'doc-json-1';
      final storage = await CRDTHive.openChangeStorageForDocument(documentId);

      final id = OperationId(
        PeerId.generate(),
        HybridLogicalClock(l: 123, c: 4),
      );

      final payload = <String, dynamic>{
        'k1': 'v1',
        'nested': {'a': 1, 'b': true},
        'list': [1, 2, 3],
      };

      final change = Change.fromPayload(
        id: id,
        deps: {},
        author: id.peerId,
        payload: payload,
      );

      await storage.saveChange(change);

      await CRDTHive.closeAllBoxes();

      final reopened = await CRDTHive.openChangeStorageForDocument(documentId);
      final changes = reopened.getChanges();

      expect(changes.length, 1);
      expect(changes.first.payload, payload);
      expect(reopened.isEmpty, isFalse);
      expect(reopened.isNotEmpty, isTrue);
      expect(changes.first.id, id);
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
  });
}
