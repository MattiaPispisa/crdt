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

  // Box names of its own for every test of the backend suite, which reuses
  // the ids `doc-a` and `doc-b`. On the VM a fresh temp directory already
  // keeps one test out of the next; on the web a box is an IndexedDB database
  // named after the box alone, `Hive.init` ignores the path, and
  // `Hive.deleteFromDisk` walks the boxes that are still open — so after
  // `closeAllBoxes` it deletes nothing and the rows of the test before are
  // still there.
  var run = 0;
  var suffix = '';

  setUp(() async {
    suffix = '-${run++}';
    Hive.init(await hiveTestPath());
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    await Hive.deleteFromDisk();
  });

  Future<CRDTHiveBackend> openBackend() => CRDTHive.open(
        changesBoxName: 'changes$suffix',
        snapshotsBoxName: 'snapshots$suffix',
        peerIdsBoxName: 'peer_ids$suffix',
        registryBoxName: 'documents$suffix',
      );

  runStorageBackendConformanceTests(
    name: 'CRDTHive',
    open: openBackend,
    // Hive keeps a box open once, so reopening means closing every box first.
    reopen: (_) async {
      await CRDTHive.closeAllBoxes();
      return openBackend();
    },
  );

  runDocumentStorageConformanceTests(
    name: 'CRDTHive',
    open: CRDTHive.openStorageForDocument,
    synchronous: true,
    openPeerIds: CRDTHive.openPeerIdStorageForDocument,
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

    test('close leaves the boxes of other documents open', () async {
      final mine = await CRDTHive.openStorageForDocument('doc-close-mine');
      final other = await CRDTHive.openStorageForDocument('doc-close-other');

      await mine.close();

      expect((mine.changes as CRDTHiveChangeStorage).box.isOpen, isFalse);
      expect((mine.snapshots as CRDTHiveSnapshotStorage).box.isOpen, isFalse);
      expect((other.changes as CRDTHiveChangeStorage).box.isOpen, isTrue);
      expect((other.snapshots as CRDTHiveSnapshotStorage).box.isOpen, isTrue);
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

    test('deleteDocument removes both boxes', () async {
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
      await CRDTHive.deleteDocument(documentId);

      final reopened = await CRDTHive.openStorageForDocument(documentId);
      expect(await reopened.changes.count, 0);
      expect(await reopened.snapshots.count, 0);
    });
  });
  group('documentBoxNameFor', () {
    test('leaves an already safe id exactly as it was', () {
      // A store written before the escaping keeps working for these.
      expect(documentBoxNameFor('changes', 'note-1'), 'changes_note-1');
    });

    test('two ids that differ only in case get two boxes', () {
      // Hive lower-cases every box name, so the raw ids would collide and the
      // two documents would merge into one.
      expect(
        documentBoxNameFor('changes', 'Note'),
        isNot(documentBoxNameFor('changes', 'note')),
      );
    });

    test('a non-ASCII id gives an ASCII name', () {
      final name = documentBoxNameFor('changes', 'nota-caffè');

      expect(name.codeUnits.every((unit) => unit < 128), isTrue);
      expect(name, isNot(contains('è')));
    });

    test('the separator cannot be forged from a prefix', () {
      expect(
        documentBoxNameFor('changes_a', 'b'),
        isNot(documentBoxNameFor('changes', 'a_b')),
      );
    });
  });
}
