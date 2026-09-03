import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

import 'helpers/hive_test_path.dart';

void main() {
  setUpAll(CRDTHive.initialize);

  setUp(() async {
    Hive.init(await hiveTestPath());
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    await Hive.deleteFromDisk();
  });

  runDocumentStorageConformanceTests(
    name: 'CRDTHive',
    open: CRDTHive.openStorageForDocument,
    // Hive keeps a box open once, so reopening means closing every box first.
    dispose: (_) => CRDTHive.closeAllBoxes(),
  );

  group('CRDTHive', () {
    test('openStorageForDocument returns the hive storages', () async {
      final storage = await CRDTHive.openStorageForDocument('doc');

      expect(storage.documentId, 'doc');
      expect(storage.changes, isA<CRDTHiveChangeStorage>());
      expect(storage.snapshots, isA<CRDTHiveSnapshotStorage>());
    });

    test('every document gets its own boxes', () async {
      final storage = await CRDTHive.openStorageForDocument('doc-boxes');

      expect(
        (storage.changes as CRDTHiveChangeStorage).box.name,
        'changes_doc-boxes',
      );
      expect(
        (storage.snapshots as CRDTHiveSnapshotStorage).box.name,
        'snapshots_doc-boxes',
      );
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

    test('deleteDocumentData removes both boxes', () async {
      const documentId = 'doc-del-data';
      final storage = await CRDTHive.openStorageForDocument(documentId);
      final id = OperationId(PeerId.generate(), HybridLogicalClock(l: 5, c: 1));

      await storage.changes.saveChange(
        Change.fromPayloadBytes(
          id: id,
          deps: const {},
          author: id.peerId,
          payloadBytes: Uint8List.fromList(const [9, 8, 7]),
        ),
      );
      await storage.snapshots.saveSnapshot(
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

      final reopened = await CRDTHive.openStorageForDocument(documentId);
      expect(await reopened.changes.count, 0);
      expect(await reopened.snapshots.count, 0);
    });
  });
}
