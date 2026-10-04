import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
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
      int? keepSnapshots = 1,
      Duration writeDelay = _now,
      void Function(Object, StackTrace)? onError,
    }) =>
        CRDTDocumentPersistence.open(
          to ?? document,
          storage,
          writeDelay: writeDelay,
          compactAfter: compactAfter,
          keepSnapshots: keepSnapshots,
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

    test('replacing the snapshot reads no snapshot back', () async {
      final snapshots = _CountingSnapshotStorage('doc');
      final storage = CRDTDocumentStorage(
        changes: InMemoryChangeStorage('doc'),
        snapshots: snapshots,
      );
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: _now,
      );
      final afterRestore = snapshots.reads;

      text.insert(0, 'a');
      document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      text.insert(1, 'b');
      document.takeSnapshot(pruneHistory: false);
      await persistence.flush();

      expect(
        snapshots.reads,
        afterRestore,
        reason: 'which snapshot to replace is already known, so reading every '
            'one of them back would decode the whole previous state',
      );
      expect(snapshots.count, 1);

      await persistence.dispose();
    });

    test('a restore drops the snapshots it did not restore from', () async {
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

      final next = reopened();
      final restored =
          await CRDTDocumentPersistence.open(next.document, storage);
      await restored.flush();

      final stored = await storage.snapshots.getSnapshots();
      expect(stored.single.id, second.id);
      await restored.dispose();
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

    test('a change pruned before it was ever written stays off the disk',
        () async {
      // A long delay, so the edits are still queued when the snapshot prunes
      // them. Written afterwards they would land after the delete meant to
      // remove them, and no later prune would name them again: a prune only
      // reports what the document still holds.
      final persistence = await attach(
        writeDelay: const Duration(seconds: 5),
      );
      text.insert(0, 'abc');
      expect(await storage.changes.count, 0);

      document.takeSnapshot();
      await persistence.flush();

      expect(await storage.changes.count, 0);

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);
      expect(next.text.value, 'abc');

      await persistence.dispose();
    });

    test('a change pruned while a failed write held it stays off the disk',
        () async {
      // The write is in flight when the prune happens, so the change it
      // carries is not in the queue for the prune to drop. The write then
      // fails and puts it back — after the prune has already been told about
      // it. Written from there it would land after the delete meant to remove
      // it, and no later prune would ever name it again.
      final storage = _GatedStorage('doc');
      final gate = Completer<void>();
      storage.gated.gate = gate;

      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: _now,
        onError: (_, __) {},
      );

      text.insert(0, 'abc');
      await storage.gated.started.future;

      document.takeSnapshot();
      // The events reach the persistence on a microtask, so the prune is
      // queued behind the write that is still failing.
      await Future<void>.delayed(Duration.zero);
      gate.complete();

      await persistence.flush();

      final onDisk = (await storage.changes.getChanges()).map((c) => c.id);
      final held = document.exportChanges().map((c) => c.id).toSet();
      expect(
        onDisk.where((id) => !held.contains(id)),
        isEmpty,
        reason: 'the store holds a change the prune removed',
      );

      await persistence.dispose();
      final next = reopened();
      await (await CRDTDocumentPersistence.open(next.document, storage))
          .dispose();
      expect(next.text.value, 'abc');
    });

    test('a prune rewrites a survivor that is still waiting in the queue',
        () async {
      // A long delay, so both edits are still queued when the prune runs. The
      // second one depends on the first, and the prune drops the first: the
      // queued bytes still name a dependency that is gone. Written as they
      // are, a reload could not replay them.
      final persistence = await attach(
        writeDelay: const Duration(seconds: 5),
      );

      text.insert(0, 'a');
      final coveredByTheSnapshot = document.takeSnapshot(pruneHistory: false);
      text.insert(1, 'b');

      document.garbageCollect(coveredByTheSnapshot.versionVector);
      await persistence.flush();

      final onDisk = await storage.changes.getChanges();
      expect(onDisk, hasLength(1));
      expect(
        onDisk.single.deps,
        isEmpty,
        reason: 'the queue holds the rewritten survivor, not its old bytes',
      );

      final next = reopened();
      await CRDTDocumentPersistence.open(next.document, storage);
      expect(next.text.value, 'ab');

      await persistence.dispose();
    });

    test('a write that fails without suspending keeps its batch queued',
        () async {
      final storage = _SyncFailingStorage('doc');
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: _now,
        onError: (_, __) {},
      );

      text.insert(0, 'a');
      await persistence.flush();
      expect(persistence.hasUnwrittenChanges, isTrue);
      expect(storage.sync.saved, isEmpty);

      storage.sync.failing = false;
      await persistence.flush();

      expect(persistence.hasUnwrittenChanges, isFalse);
      expect(storage.sync.saved, hasLength(1));
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

    test('the compaction a flush causes is written by the next flush',
        () async {
      final persistence = await attach(compactAfter: 1);

      // Two calls, so two transactions, so two changes: the store goes past
      // the limit of one.
      text
        ..insert(0, 'a')
        ..insert(1, 'b');
      await persistence.flush();
      await persistence.flush();

      expect(await storage.snapshots.count, 1);
      expect(await storage.changes.count, 0);

      await persistence.dispose();
    });

    test(
        'flush returns once what was queued at the call is written, while '
        'edits keep coming', () async {
      final changes = _TypingChangeStorage('doc');
      final persistence = await CRDTDocumentPersistence.open(
        document,
        CRDTDocumentStorage(
          changes: changes,
          snapshots: InMemorySnapshotStorage('doc'),
        ),
        writeDelay: const Duration(hours: 1),
      );
      text.insert(0, 'a');
      final queued = document.getVersionVector();
      // Every write brings a new edit, as a typist that never stops.
      changes.onSave = () => text.insert(text.length, 'x');

      await persistence.flush().timeout(const Duration(seconds: 5));
      await pumpEventQueue();

      expect(
        persistence.storedVersion.isStrictlyNewerOrEqualThan(queued),
        isTrue,
      );
      expect(
        persistence.hasUnwrittenChanges,
        isTrue,
        reason: 'the edits made after the call wait for the next write',
      );
      changes.onSave = null;
      await persistence.dispose();
      expect(persistence.hasUnwrittenChanges, isFalse);
    });

    test('compact snapshots, prunes, and waits for the disk', () async {
      final persistence = await attach(writeDelay: const Duration(seconds: 5));
      text.insert(0, 'abc');

      final snapshot = await persistence.compact();

      expect((await storage.snapshots.getSnapshots()).single.id, snapshot.id);
      expect(
        await storage.changes.count,
        0,
        reason: 'the history the snapshot covers is gone, disk included',
      );

      await persistence.dispose();
      final next = reopened();
      await (await CRDTDocumentPersistence.open(next.document, storage))
          .dispose();
      expect(next.text.value, 'abc');
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

    test('a failed write is retried without a flush and without a new edit',
        () async {
      final storage = _FailingStorage('doc', failures: 1);
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: _now,
        onError: (_, __) {},
      );

      text.insert(0, 'a');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        persistence.hasUnwrittenChanges,
        isTrue,
        reason: 'the first write failed',
      );

      // Nothing is called here. A document that goes quiet after a failure
      // would otherwise keep its changes in memory and nowhere else.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(persistence.hasUnwrittenChanges, isFalse);
      expect(await storage.changes.count, 1);
      await persistence.dispose();
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

    group('keepSnapshots', () {
      /// Takes [count] snapshots, one edit apart, and returns their ids.
      Future<List<String>> snapshot(
        CRDTDocumentPersistence persistence,
        int count,
      ) async {
        final ids = <String>[];
        for (var i = 0; i < count; i++) {
          text.insert(text.length, '$i');
          ids.add(document.takeSnapshot(pruneHistory: false).id);
          await persistence.flush();
        }
        return ids;
      }

      Future<List<String>> storedIds() async => [
            for (final snapshot in await storage.snapshots.getSnapshots())
              snapshot.id,
          ];

      test('has to be positive', () {
        expect(
          () => attach(keepSnapshots: 0),
          throwsA(isA<AssertionError>()),
        );
      });

      test('keeps that many of the newest snapshots', () async {
        final persistence = await attach(keepSnapshots: 3);
        final ids = await snapshot(persistence, 5);

        expect(await storedIds(), unorderedEquals(ids.skip(2)));
        await persistence.dispose();
      });

      test('null keeps every snapshot', () async {
        final persistence = await attach(keepSnapshots: null);
        final ids = await snapshot(persistence, 4);

        expect(await storedIds(), unorderedEquals(ids));
        await persistence.dispose();
      });

      test('a restore drops the oldest beyond the limit', () async {
        final persistence = await attach(keepSnapshots: null);
        final ids = await snapshot(persistence, 3);
        await persistence.dispose();

        final next = reopened();
        final restored = await CRDTDocumentPersistence.open(
          next.document,
          storage,
          keepSnapshots: 2,
        );
        await restored.flush();

        expect(await storedIds(), unorderedEquals(ids.skip(1)));
        expect(next.text.value, '012');
        await restored.dispose();
      });
    });

    group('a snapshot write that fails', () {
      late _FailingSnapshotStorage snapshots;
      late CRDTDocumentPersistence persistence;

      setUp(() async {
        snapshots = _FailingSnapshotStorage('doc');
        storage = InMemoryDocumentStorage('doc');
        persistence = await CRDTDocumentPersistence.open(
          document,
          CRDTDocumentStorage(changes: storage.changes, snapshots: snapshots),
          writeDelay: _now,
          onError: (_, __) {},
        );
        text.insert(0, 'abc');
        await persistence.flush();
      });

      tearDown(() async {
        snapshots.failing = false;
        await persistence.dispose();
      });

      test('holds back its prune, and is tried again', () async {
        final written = await storage.changes.count;

        document.takeSnapshot();
        await persistence.flush();

        expect(snapshots.count, 0);
        expect(
          await storage.changes.count,
          written,
          reason: 'the prune waits for the snapshot that covers it',
        );
        expect(persistence.hasUnwrittenChanges, isTrue);

        snapshots.failing = false;
        await persistence.flush();

        expect(snapshots.count, 1);
        expect(await storage.changes.count, 0);
        expect(persistence.hasUnwrittenChanges, isFalse);
      });

      test('makes flush(throwOnError: true) throw, in every caller', () async {
        document.takeSnapshot();

        final results = await Future.wait(
          [
            persistence.flush(throwOnError: true).then((_) => 'ok'),
            persistence.flush(throwOnError: true).then((_) => 'ok'),
          ].map((flush) => flush.catchError((Object _) => 'thrown')),
        );

        expect(results, ['thrown', 'thrown']);
      });

      test('makes compact throw', () async {
        await expectLater(persistence.compact(), throwsStateError);
      });
    });

    group('whenStored', () {
      test('completes once the changes are on the storage, not before',
          () async {
        final persistence = await attach(writeDelay: const Duration(hours: 1));
        text.insert(0, 'a');

        var done = false;
        final stored = persistence
            .whenStored(document.getVersionVector())
            .then((_) => done = true);
        await pumpEventQueue();
        expect(done, isFalse);

        await persistence.flush();
        await stored;
        expect(await storage.changes.count, 1);
        await persistence.dispose();
      });

      test('waits through a failed write, and completes once a retry lands',
          () async {
        final persistence = await CRDTDocumentPersistence.open(
          document,
          _FailingStorage('doc', failures: 1),
          writeDelay: _now,
          onError: (_, __) {},
        );
        text.insert(0, 'a');

        var done = false;
        final stored = persistence
            .whenStored(document.getVersionVector())
            .then((_) => done = true);
        await persistence.flush();
        await pumpEventQueue();
        expect(done, isFalse, reason: 'the first write failed');

        await persistence.flush();
        await stored;
        await persistence.dispose();
      });

      test('counts what a reopen read back, from every peer', () async {
        final remote = CRDTDocument(documentId: 'doc');
        CRDTFugueTextHandler(remote, 'text').insert(0, 'theirs');
        final persistence = await attach();
        text.insert(0, 'mine ');
        document.importChanges(remote.exportChanges());
        await persistence.dispose();

        final next = reopened();
        final restored = await attach(to: next.document);

        expect(
          restored.storedVersion
              .isStrictlyNewerOrEqualThan(next.document.getVersionVector()),
          isTrue,
        );
        await restored.dispose();
      });

      test(
          'counts a snapshot for the changes it pruned before they were '
          'written', () async {
        final persistence = await attach(writeDelay: const Duration(hours: 1));
        text.insert(0, 'a');
        final snapshot = document.takeSnapshot();

        await persistence.whenStored(snapshot.versionVector);

        expect(await storage.changes.count, 0);
        await persistence.dispose();
      });

      test('throws at dispose for a version the storage never got', () async {
        final persistence = await CRDTDocumentPersistence.open(
          document,
          _FailingStorage('doc'),
          writeDelay: _now,
          onError: (_, __) {},
        );
        text.insert(0, 'a');
        final version = document.getVersionVector();
        final outcome = expectLater(
          persistence.whenStored(version),
          throwsStateError,
        );

        await persistence.dispose();
        await outcome;
        await expectLater(persistence.whenStored(version), throwsStateError);
      });
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
    group('a document edited before open', () {
      // The bug this pins: nothing reported those changes — an event is only
      // built once something listens, and the persistence subscribes at
      // `open`. They stayed in memory, while the changes written after them
      // reached the disk naming dependencies that were never stored.
      test('is written whole, not from the first edit after open', () async {
        text.insert(0, 'before');

        final persistence = await attach();
        text.insert(text.length, ' and after');
        await persistence.dispose();

        final read = await storage.readDocument();
        expect(CRDTFugueTextHandler(read, 'text').value, 'before and after');
      });

      test('keeps a snapshot taken before open', () async {
        text.insert(0, 'abc');
        document.takeSnapshot();

        final persistence = await attach();
        await persistence.whenStored(document.getVersionVector());
        await persistence.dispose();

        final next = reopened();
        final restored = await attach(to: next.document);
        expect(next.text.value, 'abc');
        expect(
          restored.hasUnwrittenChanges,
          isFalse,
          reason: 'the snapshot read back is already on the disk',
        );
        await restored.dispose();
      });

      test('writes its snapshot over the older one on the disk', () async {
        final first = await attach();
        text.insert(0, 'abc');
        await first.compact();
        await first.dispose();

        text.insert(3, 'd');
        final newer = document.takeSnapshot();

        final second = await attach();
        await second.whenStored(newer.versionVector);
        await second.flush();
        expect((await storage.snapshots.getSnapshots()).single.id, newer.id);
        await second.dispose();

        final next = reopened();
        await (await attach(to: next.document)).dispose();
        expect(next.text.value, 'abcd');
      });

      test(
          'throws on a stored snapshot concurrent with its own, and stops '
          'following', () async {
        final theirs = CRDTDocument(documentId: 'doc');
        CRDTFugueTextHandler(theirs, 'text').insert(0, 'BBB');
        final stored = theirs.takeSnapshot();
        await storage.snapshots.saveSnapshot(stored);
        text.insert(0, 'AAA');
        document.takeSnapshot();

        await expectLater(
          attach(),
          throwsA(isA<ConcurrentSnapshotException>()),
        );
        expect(text.value, 'AAA', reason: 'the document is left as it was');

        text.insert(3, '!');
        await pumpEventQueue();
        expect(await storage.changes.count, 0);
        expect((await storage.snapshots.getSnapshots()).single.id, stored.id);
      });

      test(
          'openSync throws on a concurrent stored snapshot, and stops '
          'following', () async {
        final theirs = CRDTDocument(documentId: 'doc');
        CRDTFugueTextHandler(theirs, 'text').insert(0, 'BBB');
        await storage.snapshots.saveSnapshot(theirs.takeSnapshot());
        text.insert(0, 'AAA');
        document.takeSnapshot();

        expect(
          () => CRDTDocumentPersistence.openSync(document, storage),
          throwsA(isA<ConcurrentSnapshotException>()),
        );

        text.insert(3, '!');
        await pumpEventQueue();
        expect(await storage.changes.count, 0);
      });

      test('queues nothing when the storage already holds it', () async {
        text.insert(0, 'hello');
        await (await attach()).dispose();

        final reopened = CRDTDocument(documentId: 'doc');
        final second = await attach(to: reopened);

        expect(second.hasUnwrittenChanges, isFalse);
        await second.dispose();
        reopened.dispose();
      });
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

/// A storage whose first `failures` writes fail.
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

/// A change storage that runs [onSave] on every write, before it saves.
class _TypingChangeStorage extends InMemoryChangeStorage {
  _TypingChangeStorage(super.documentId);

  void Function()? onSave;

  @override
  void saveChanges(List<Change> changes) {
    onSave?.call();
    super.saveChanges(changes);
  }
}

/// A snapshot storage that refuses every write while [failing] is on.
class _FailingSnapshotStorage extends InMemorySnapshotStorage {
  _FailingSnapshotStorage(super.documentId);

  bool failing = true;

  @override
  Future<void> saveSnapshot(Snapshot snapshot) async {
    if (failing) {
      throw StateError('disk full');
    }
    return super.saveSnapshot(snapshot);
  }
}

/// A storage that counts how often its snapshots are read back.
class _CountingSnapshotStorage extends InMemorySnapshotStorage {
  _CountingSnapshotStorage(super.documentId);

  /// How many times [getSnapshots] was called.
  int reads = 0;

  @override
  List<Snapshot> getSnapshots() {
    reads += 1;
    return super.getSnapshots();
  }
}

/// A storage whose next write waits for the test, and then fails.
class _GatedStorage extends CRDTDocumentStorage {
  _GatedStorage(String documentId)
      : super(
          changes: _GatedChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );

  /// The change storage, as what it really is.
  _GatedChangeStorage get gated => changes as _GatedChangeStorage;
}

class _GatedChangeStorage extends InMemoryChangeStorage {
  _GatedChangeStorage(super.documentId);

  /// Set by the test to hold the next write open; every write after it lands
  /// normally.
  Completer<void>? gate;

  /// Completes once the held write has started.
  final Completer<void> started = Completer<void>();

  @override
  Future<void> saveChanges(List<Change> changes) async {
    final gate = this.gate;
    if (gate == null) {
      return super.saveChanges(changes);
    }

    this.gate = null;
    started.complete();
    await gate.future;
    throw StateError('disk full');
  }
}

/// A storage that refuses a write without suspending first.
class _SyncFailingStorage extends CRDTDocumentStorage {
  _SyncFailingStorage(String documentId)
      : super(
          changes: _SyncFailingChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );

  /// The change storage, as what it really is.
  _SyncFailingChangeStorage get sync => changes as _SyncFailingChangeStorage;
}

class _SyncFailingChangeStorage extends InMemoryChangeStorage {
  _SyncFailingChangeStorage(super.documentId);

  /// While this is on, a write throws before it saves anything.
  bool failing = true;

  /// What reached the storage.
  List<Change> get saved => getChanges();

  @override
  void saveChanges(List<Change> changes) {
    if (failing) {
      throw StateError('disk full');
    }
    return super.saveChanges(changes);
  }
}
