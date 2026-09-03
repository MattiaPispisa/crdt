import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('CRDTDocument.events', () {
    late CRDTDocument doc;
    late Handler<dynamic> handler;
    late List<CRDTDocumentEvent> events;
    late StreamSubscription<CRDTDocumentEvent> subscription;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      handler = TestHandler(doc);
      events = <CRDTDocumentEvent>[];
      subscription = doc.events.listen(events.add);
    });

    tearDown(() async {
      await subscription.cancel();
    });

    Operation newOperation() => TestOperation.fromHandler(handler);

    /// A second document sharing [handler]'s id, so the changes it writes
    /// target the same handler once they reach [doc].
    CRDTDocument remoteDocument() {
      final remote = CRDTDocument(peerId: PeerId.generate());
      TestHandler(remote);
      return remote;
    }

    /// A change written by [remote] against the shared handler.
    Change remoteChange(CRDTDocument remote) => remote.createChange(
          TestOperation.fromHandler(remote.registeredHandlers[handler.id]!),
        );

    List<T> only<T extends CRDTDocumentEvent>() =>
        events.whereType<T>().toList();

    group('changes', () {
      test('createChange reports the change as created', () async {
        final change = doc.createChange(newOperation());
        await pumpEventQueue();

        final applied = only<DocumentChangesApplied>();
        expect(applied, hasLength(1));
        expect(applied.single.source, ChangeSource.created);
        expect(applied.single.changes, [change]);
      });

      test('a transaction reports one event, not one per operation', () async {
        doc.runInTransaction(() {
          doc
            ..registerOperation(newOperation())
            ..registerOperation(newOperation());
        });
        await pumpEventQueue();

        final applied = only<DocumentChangesApplied>();
        expect(applied, hasLength(1));
        expect(applied.single.source, ChangeSource.created);
        expect(applied.single.changes, hasLength(2));
      });

      test('applyChange reports the change as ingested', () async {
        final change = remoteChange(remoteDocument());

        doc.applyChange(change);
        await pumpEventQueue();

        final applied = only<DocumentChangesApplied>();
        expect(applied, hasLength(1));
        expect(applied.single.source, ChangeSource.ingested);
        expect(applied.single.changes, [change]);
      });

      test('importChanges reports the applied changes as ingested', () async {
        final remote = remoteDocument();
        remoteChange(remote);
        remoteChange(remote);

        final imported = doc.importChanges(remote.exportChanges());
        await pumpEventQueue();

        expect(imported, 2);
        final applied = only<DocumentChangesApplied>();
        expect(applied, hasLength(1));
        expect(applied.single.source, ChangeSource.ingested);
        expect(applied.single.changes, hasLength(2));
      });

      test('a change the document already holds is not reported again',
          () async {
        final change = remoteChange(remoteDocument());

        doc
          ..applyChange(change)
          ..applyChange(change);
        await pumpEventQueue();

        expect(only<DocumentChangesApplied>(), hasLength(1));
      });

      test('a transaction that ingests then writes reports them in that order',
          () async {
        final remote = remoteDocument();
        final theirs = remoteChange(remote);
        events.clear();

        doc.runInTransaction(() {
          doc
            ..importChanges([theirs])
            ..createChange(newOperation());
        });
        await pumpEventQueue();

        // The ingest happened first, and the change the document went on to
        // write names [theirs] among its dependencies. Reporting the two the
        // other way round would describe a history that cannot be replayed.
        expect(
          only<DocumentChangesApplied>().map((e) => e.source),
          [ChangeSource.ingested, ChangeSource.created],
        );
      });

      test('carries the origin the call was tagged with', () async {
        final tag = Object();
        doc.runInTransaction(
          () => doc.registerOperation(newOperation()),
          origin: tag,
        );
        await pumpEventQueue();

        expect(only<DocumentChangesApplied>().single.origin, same(tag));
      });
    });

    group('snapshots', () {
      test('takeSnapshot reports the snapshot it returns', () async {
        doc.createChange(newOperation());
        final snapshot = doc.takeSnapshot(pruneHistory: false);
        await pumpEventQueue();

        final updated = only<DocumentSnapshotUpdated>();
        expect(updated, hasLength(1));
        expect(updated.single.reason, SnapshotReason.taken);
        expect(updated.single.snapshot, same(snapshot));
      });

      test('importSnapshot reports the imported snapshot', () async {
        final remote = remoteDocument();
        remoteChange(remote);
        final snapshot = remote.takeSnapshot(pruneHistory: false);

        expect(doc.importSnapshot(snapshot), isTrue);
        await pumpEventQueue();

        final updated = only<DocumentSnapshotUpdated>();
        expect(updated, hasLength(1));
        expect(updated.single.reason, SnapshotReason.imported);
        expect(updated.single.snapshot, same(snapshot));
      });

      test('a snapshot that is not applied reports nothing', () async {
        doc.createChange(newOperation());
        final newer = doc.takeSnapshot(pruneHistory: false);
        await pumpEventQueue();
        events.clear();

        final older = Snapshot(
          id: 'older',
          versionVector: VersionVector({}),
          data: newer.data,
        );
        expect(doc.importSnapshot(older), isFalse);
        await pumpEventQueue();

        expect(only<DocumentSnapshotUpdated>(), isEmpty);
      });

      test('mergeSnapshot reports the merged result, not the input', () async {
        doc
          ..createChange(newOperation())
          ..takeSnapshot(pruneHistory: false);
        await pumpEventQueue();
        events.clear();

        final otherPeer = PeerId.generate();
        final other = Snapshot(
          id: 'other',
          versionVector: VersionVector({otherPeer: doc.hlc}),
          data: const {},
        );
        doc.mergeSnapshot(other, pruneHistory: false);
        await pumpEventQueue();

        final updated = only<DocumentSnapshotUpdated>();
        expect(updated, hasLength(1));
        expect(updated.single.reason, SnapshotReason.merged);
        expect(updated.single.snapshot, isNot(same(other)));
        // Both peers: the merge kept what the document already had.
        expect(updated.single.snapshot.versionVector.entries, hasLength(2));
      });
    });

    group('prune', () {
      test('reports the changes that left the store', () async {
        doc
          ..createChange(newOperation())
          ..createChange(newOperation());
        await pumpEventQueue();
        events.clear();

        doc.takeSnapshot();
        await pumpEventQueue();

        final pruned = only<DocumentHistoryPruned>();
        expect(pruned, hasLength(1));
        expect(pruned.single.removed, hasLength(2));
        expect(pruned.single.rewritten, isEmpty);
        expect(doc.exportChanges(), isEmpty);
      });

      test('reports the surviving changes whose deps were rebuilt', () async {
        // A change of this peer, then one of another peer depending on it.
        // Pruning up to this peer's clock alone drops the first and strips the
        // dependency the second can no longer name.
        doc.createChange(newOperation());

        final remote = remoteDocument()..importChanges(doc.exportChanges());
        final survivor = remoteChange(remote);
        doc.applyChange(survivor);
        expect(survivor.deps, isNotEmpty);

        doc.takeSnapshot(pruneHistory: false);
        await pumpEventQueue();
        events.clear();

        doc.garbageCollect(
          VersionVector({doc.peerId: doc.getVersionVector()[doc.peerId]!}),
        );
        await pumpEventQueue();

        final pruned = only<DocumentHistoryPruned>();
        expect(pruned, hasLength(1));
        expect(pruned.single.removed, hasLength(1));
        expect(pruned.single.rewritten, hasLength(1));
        expect(pruned.single.rewritten.single.id, survivor.id);
        expect(pruned.single.rewritten.single.deps, isEmpty);
      });

      test('a prune that removes nothing reports nothing', () async {
        doc.createChange(newOperation());
        await pumpEventQueue();
        events.clear();

        doc.garbageCollect(VersionVector({}));
        await pumpEventQueue();

        expect(only<DocumentHistoryPruned>(), isEmpty);
      });

      test('the snapshot is reported before the prune it causes', () async {
        doc.createChange(newOperation());
        await pumpEventQueue();
        events.clear();

        doc.takeSnapshot();
        await pumpEventQueue();

        expect(
          events.indexWhere((e) => e is DocumentSnapshotUpdated),
          lessThan(events.indexWhere((e) => e is DocumentHistoryPruned)),
        );
      });
    });

    group('origin', () {
      test('a snapshot and the prune it causes carry the origin', () async {
        final tag = Object();
        doc.createChange(newOperation());
        await pumpEventQueue();
        events.clear();

        doc.takeSnapshot(origin: tag);
        await pumpEventQueue();

        expect(only<DocumentSnapshotUpdated>().single.origin, same(tag));
        expect(only<DocumentHistoryPruned>().single.origin, same(tag));
      });

      test('import tags the snapshot it applies, not only the changes',
          () async {
        final tag = Object();
        final remote = remoteDocument();
        remoteChange(remote);
        final snapshot = remote.takeSnapshot(pruneHistory: false);
        // After the snapshot, so the change is not one the snapshot covers.
        final change = remoteChange(remote);
        events.clear();

        doc.import(
          snapshot: snapshot,
          changes: [change],
          merge: true,
          pruneHistory: false,
          origin: tag,
        );
        await pumpEventQueue();

        expect(only<DocumentSnapshotUpdated>().single.origin, same(tag));
        expect(only<DocumentChangesApplied>().single.origin, same(tag));
      });

      test('a nested call keeps its own origin, not the one at commit',
          () async {
        final outer = Object();
        final inner = Object();
        final remote = remoteDocument();
        final theirs = remoteChange(remote);
        events.clear();

        doc.runInTransaction(
          origin: outer,
          () => doc.importChanges([theirs], origin: inner),
        );
        await pumpEventQueue();

        // The import is over long before the commit runs, and it restored
        // [outer] on its way out. The batch has to remember the origin of the
        // call that made it, or a consumer cannot recognise its own writes.
        expect(only<DocumentChangesApplied>().single.origin, same(inner));
      });

      test('garbageCollect carries the origin', () async {
        final tag = Object();
        doc
          ..createChange(newOperation())
          ..takeSnapshot(pruneHistory: false);
        await pumpEventQueue();
        events.clear();

        doc.garbageCollect(doc.getVersionVector(), origin: tag);
        await pumpEventQueue();

        expect(only<DocumentHistoryPruned>().single.origin, same(tag));
      });
    });

    group('delivery', () {
      test('events arrive only once the document is settled', () async {
        final changeCountWhenDelivered = <int>[];
        doc.events.listen(
          (_) => changeCountWhenDelivered.add(doc.exportChanges().length),
        );

        doc.runInTransaction(() {
          doc
            ..registerOperation(newOperation())
            ..registerOperation(newOperation());
        });
        await pumpEventQueue();

        // One event for the whole transaction, and the document already holds
        // both changes when it lands — never a half-applied read.
        expect(changeCountWhenDelivered, [2]);
      });

      test('the stream closes on dispose', () async {
        final done = expectLater(doc.events, emitsThrough(emitsDone));
        doc.dispose();
        await done;
      });
    });
  });

  group('CRDTDocument.localChanges', () {
    late CRDTDocument doc;
    late Handler<dynamic> handler;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      handler = TestHandler(doc);
    });

    test('does not carry a change that came in through applyChange', () async {
      final remote = CRDTDocument(peerId: PeerId.generate());
      TestHandler(remote);
      final theirs = remote.createChange(
        TestOperation.fromHandler(remote.registeredHandlers[handler.id]!),
      );

      final seen = <Change>[];
      doc.localChanges.listen(seen.add);

      doc.applyChange(theirs);
      final mine = doc.createChange(TestOperation.fromHandler(handler));
      await pumpEventQueue();

      expect(seen, [mine]);
    });
  });
}
