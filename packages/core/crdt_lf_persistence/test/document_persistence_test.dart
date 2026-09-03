import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:test/test.dart';

/// No delay, so a test does not wait on a timer it does not care about.
const Duration _now = Duration.zero;

void main() {
  group('CRDTDocumentPersistence', () {
    late InMemoryDocumentStorage storage;
    late CRDTDocument document;
    late CRDTFugueTextHandler text;

    setUp(() {
      storage = InMemoryDocumentStorage('doc');
      document = CRDTDocument(documentId: 'doc');
      text = CRDTFugueTextHandler(document, 'text');
    });

    Future<CRDTDocumentPersistence> attach({
      CRDTDocument? to,
      int? compactAfter,
      void Function(Object, StackTrace)? onError,
    }) =>
        CRDTDocumentPersistence.open(
          to ?? document,
          storage,
          writeDelay: _now,
          compactAfter: compactAfter,
          onError: onError,
        );

    /// A second document on the same storage, as a restart would give.
    ({CRDTDocument document, CRDTFugueTextHandler text}) reopened() {
      final next = CRDTDocument(documentId: 'doc');
      return (document: next, text: CRDTFugueTextHandler(next, 'text'));
    }

    test('writes what the document holds, and reads it back', () async {
      final persistence = await attach();
      text.insert(0, 'Hello 🌍');
      await persistence.dispose();

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);

      expect(next.text.value, 'Hello 🌍');
    });

    test('saves the changes it took in, not only the ones it wrote', () async {
      final remote = CRDTDocument(documentId: 'doc');
      CRDTFugueTextHandler(remote, 'text').insert(0, 'theirs');

      final persistence = await attach();
      document.importChanges(remote.exportChanges());
      await persistence.dispose();

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);

      expect(next.text.value, 'theirs');
    });

    test('a change written while the storage is being read is not lost',
        () async {
      // Seed the storage, so the restore has something to read.
      final seed = await attach();
      text.insert(0, 'a');
      await seed.dispose();

      final next = reopened();
      final opening = CRDTDocumentPersistence.open(
        next.document,
        storage,
        writeDelay: _now,
      );
      // Between the subscription and the end of the restore.
      next.text.insert(next.text.value.length, 'b');
      await (await opening).dispose();

      final third = reopened();
      await CRDTDocumentPersistence.open(third.document, storage);

      // Order is not the point: 'b' was written against an empty document,
      // so where the merge puts it is up to the CRDT. Losing it is the bug.
      expect(third.text.value.split(''), unorderedEquals(['a', 'b']));
    });

    test('the restore is not written back', () async {
      final seed = await attach();
      text.insert(0, 'abc');
      await seed.dispose();
      final writtenByTheSeed = await storage.changes.count;

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);
      await Future<void>.delayed(Duration.zero);

      // The restore imported everything the seed wrote; without the origin
      // tag every one of those changes would be written straight back.
      expect(await storage.changes.count, writtenByTheSeed);
    });

    test('several stored snapshots are folded, not picked between', () async {
      final other = CRDTDocument(documentId: 'doc');
      CRDTFugueTextHandler(other, 'other').insert(0, 'x');
      final persistence = await attach();
      text.insert(0, 'y');
      document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      // A write interrupted halfway can leave a second one behind.
      await storage.snapshots.saveSnapshot(other.takeSnapshot());
      await persistence.dispose();

      final next = reopened();
      final otherHandler = CRDTFugueTextHandler(next.document, 'other');
      await CRDTDocumentPersistence.open(next.document, storage);

      expect(next.text.value, 'y');
      expect(otherHandler.value, 'x');
    });

    test('a new snapshot replaces the one before it', () async {
      final persistence = await attach();
      text.insert(0, 'a');
      document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      text.insert(1, 'b');
      final second = document.takeSnapshot(pruneHistory: false);
      await persistence.flush();

      final stored = await storage.snapshots.getSnapshots();
      expect(stored, hasLength(1));
      expect(stored.single.id, second.id);

      await persistence.dispose();
    });

    test('a prune drops what left the store and rewrites what stayed',
        () async {
      final persistence = await attach();
      text.insert(0, 'abc');
      await persistence.flush();
      expect(await storage.changes.count, greaterThan(0));

      document.takeSnapshot();
      await persistence.flush();

      expect(await storage.changes.count, 0);

      // The state still comes back: it lives in the snapshot now.
      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);
      expect(next.text.value, 'abc');

      await persistence.dispose();
    });

    test('compactAfter snapshots and prunes once the log is long enough',
        () async {
      final persistence = await attach(compactAfter: 3);

      for (var i = 0; i < 6; i++) {
        text.insert(text.value.length, '$i');
        await persistence.flush();
      }

      expect(await storage.changes.count, lessThanOrEqualTo(3));
      expect(await storage.snapshots.count, 1);

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);
      expect(next.text.value, '012345');

      await persistence.dispose();
    });

    test('one flush covers the work the compaction itself causes', () async {
      final persistence = await attach(compactAfter: 1);

      // Two calls, so two transactions, so two changes: the store goes past
      // the limit of one.
      text
        ..insert(0, 'a')
        ..insert(1, 'b');
      await persistence.flush();

      // The snapshot and the prune it causes are written inside this flush,
      // not left for the next one.
      expect(await storage.snapshots.count, 1);
      expect(await storage.changes.count, 0);

      await persistence.dispose();
    });

    test('a failed write reaches onError', () async {
      final errors = <Object>[];
      final persistence = await CRDTDocumentPersistence.open(
        document,
        _FailingStorage('doc'),
        writeDelay: _now,
        onError: (error, _) => errors.add(error),
      );

      text.insert(0, 'a');
      await persistence.flush();

      expect(errors, hasLength(1));
      await persistence.dispose();
    });

    test('nothing is written after dispose', () async {
      final persistence = await attach();
      text.insert(0, 'a');
      await persistence.dispose();
      final written = await storage.changes.count;

      text.insert(1, 'b');
      await Future<void>.delayed(Duration.zero);

      expect(await storage.changes.count, written);
    });
  });
}

/// A storage whose writes always fail.
class _FailingStorage extends CRDTDocumentStorage {
  _FailingStorage(String documentId)
      : super(
          changes: _FailingChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );
}

class _FailingChangeStorage extends InMemoryChangeStorage {
  _FailingChangeStorage(super.documentId);

  @override
  Future<void> saveChanges(List<Change> changes) async =>
      throw StateError('disk full');
}
