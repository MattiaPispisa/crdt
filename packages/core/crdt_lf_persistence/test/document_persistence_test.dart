import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:test/test.dart';

import 'support/in_memory_storage.dart';

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

    test('the newest of several stored snapshots is the one restored',
        () async {
      final persistence = await attach();
      text.insert(0, 'a');
      final first = document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      text.insert(1, 'b');
      final second = document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      // A write killed between saving the new snapshot and dropping the old
      // one leaves both behind.
      await storage.snapshots.saveSnapshot(first);
      await persistence.dispose();
      expect(await storage.snapshots.count, 2);

      final next = reopened();
      final restored = <Snapshot>[];
      next.document.events.listen((event) {
        if (event is DocumentSnapshotUpdated) {
          restored.add(event.snapshot);
        }
      });
      await CRDTDocumentPersistence.open(next.document, storage);
      // The events reach a listener on a microtask.
      await Future<void>.delayed(Duration.zero);

      expect(next.text.value, 'ab');
      expect(restored.single.id, second.id);
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

    test('compactAfter has to be positive', () {
      expect(
        () => attach(compactAfter: 0),
        throwsA(isA<ArgumentError>()),
      );
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

    test('a failed write is tried again, not dropped', () async {
      final storage = _FailingStorage('doc', failures: 1);
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: _now,
        onError: (_, __) {},
      );

      text.insert(0, 'a');
      await persistence.flush();
      expect(
        persistence.hasUnwrittenChanges,
        isTrue,
        reason: 'the batch the failed write carried stays queued',
      );

      await persistence.flush();
      expect(persistence.hasUnwrittenChanges, isFalse);
      expect(await storage.changes.count, 1);

      await persistence.dispose();
      final next = reopened();
      await (await CRDTDocumentPersistence.open(next.document, storage))
          .dispose();
      expect(next.text.value, 'a');
    });

    test('a write that keeps failing leaves the changes waiting', () async {
      final persistence = await CRDTDocumentPersistence.open(
        document,
        _FailingStorage('doc'),
        writeDelay: _now,
        onError: (_, __) {},
      );

      text.insert(0, 'a');
      // The timeout is the assertion: a flush that retried a storage which
      // keeps refusing would never end.
      await persistence.flush();

      expect(persistence.hasUnwrittenChanges, isTrue);
      await persistence.dispose();
    });

    test('openSync restores before it returns', () async {
      final persistence = await attach();
      text.insert(0, 'Hello 🌍');
      await persistence.dispose();

      final next = reopened();
      CRDTDocumentPersistence.openSync(next.document, storage);

      expect(next.text.value, 'Hello 🌍');
    });

    test('openSync refuses a storage that suspends', () async {
      final slow = _SuspendingStorage('doc');
      final next = reopened();

      expect(
        () => CRDTDocumentPersistence.openSync(next.document, slow),
        throwsA(isA<StateError>()),
      );

      // The restore it started must not land, and nothing must be following
      // the document: a write after the refusal reaches no storage.
      next.text.insert(0, 'after');
      await Future<void>.delayed(_now);

      expect(next.text.value, 'after', reason: 'the restore did not land');
      expect(slow.written, isEmpty, reason: 'nothing followed the document');
    });

    test('a document reopened with its stored id stays one author', () async {
      InMemoryPeerIdStorage.reset();
      final peers = InMemoryPeerIdStorage('doc');

      final firstId = await peers.loadOrCreate();
      final first = CRDTDocument(documentId: 'doc', peerId: firstId);
      final firstText = CRDTFugueTextHandler(first, 'text');
      final firstRun = await attach(to: first);
      firstText.insert(0, 'a');
      await firstRun.dispose();

      final secondId = await peers.loadOrCreate();
      final second = CRDTDocument(documentId: 'doc', peerId: secondId);
      final secondText = CRDTFugueTextHandler(second, 'text');
      final secondRun = await attach(to: second);
      secondText.insert(1, 'b');
      await secondRun.dispose();

      expect(secondId, firstId, reason: 'the identity came back');
      expect(secondText.value, 'ab');
      expect(
        second.getVersionVector().entries.map((e) => e.key).toList(),
        [firstId],
        reason: 'a second session must not add a second author',
      );
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

/// A storage that suspends on every read, as drift does.
class _SuspendingStorage extends CRDTDocumentStorage {
  _SuspendingStorage(String documentId)
      : super(
          changes: _SuspendingChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );

  /// What reached the storage, so a test can show nothing did.
  List<Change> get written => (changes as _SuspendingChangeStorage).written;
}

class _SuspendingChangeStorage implements CRDTChangeStorage {
  _SuspendingChangeStorage(this.documentId);

  @override
  final String documentId;

  /// What reached this storage.
  final List<Change> written = <Change>[];

  @override
  Future<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) async =>
      <Change>[];

  @override
  Future<void> saveChange(Change change) async => written.add(change);

  @override
  Future<void> saveChanges(List<Change> changes) async =>
      written.addAll(changes);

  @override
  Future<bool> deleteChange(Change change) async => false;

  @override
  Future<int> deleteChanges(List<Change> changes) async => 0;

  @override
  Future<void> clear() async => written.clear();

  @override
  Future<int> get count async => written.length;
}

/// A storage whose first [failures] writes fail.
///
/// `-1` fails every write.
class _FailingStorage extends CRDTDocumentStorage {
  _FailingStorage(String documentId, {int failures = -1})
      : super(
          changes: _FailingChangeStorage(documentId, failures),
          snapshots: InMemorySnapshotStorage(documentId),
        );
}

class _FailingChangeStorage extends InMemoryChangeStorage {
  _FailingChangeStorage(super.documentId, this._failures);

  int _failures;

  @override
  Future<void> saveChanges(List<Change> changes) async {
    if (_failures != 0) {
      if (_failures > 0) {
        _failures -= 1;
      }
      throw StateError('disk full');
    }
    return super.saveChanges(changes);
  }
}
