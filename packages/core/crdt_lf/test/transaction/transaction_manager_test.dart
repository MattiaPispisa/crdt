import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('TransactionManager', () {
    late Operation dummyOperation;

    setUp(() {
      // The manager never looks inside an operation, so any real one does.
      final doc = CRDTDocument(peerId: PeerId.generate());
      dummyOperation = TestOperation.fromHandler(TestHandler(doc, id: 'dummy'));
    });

    Change changeAt(int clock) {
      final peerId = PeerId.generate();
      return Change(
        id: OperationId(peerId, HybridLogicalClock(l: clock, c: 1)),
        operation: dummyOperation,
        deps: {},
        author: peerId,
      );
    }

    DocumentChangesApplied batch(List<Change> changes, ChangeSource source) =>
        DocumentChangesApplied(changes: changes, source: source);

    test('begin/commit defers and flushes updates and local changes', () {
      final emittedOperations = <Operation>[];
      var updateCount = 0;

      final manager = TransactionManager(
        flushWork: (work) {
          emittedOperations.addAll(work.operations);
          updateCount++;
        },
      )
        // Begin transaction
        ..begin();
      expect(manager.isInTransaction, isTrue);

      // Request updates while in transaction
      manager
        ..requestUpdate()
        ..requestUpdate();
      expect(updateCount, 0);

      // Emit local changes while in transaction
      manager.handleOperation(dummyOperation);
      expect(emittedOperations, isEmpty);
      expect(updateCount, 0);

      // Commit outermost transaction -> flush once
      manager.commit();
      expect(manager.isInTransaction, isFalse);
      expect(emittedOperations.length, 1);
      expect(updateCount, 1);
    });

    test('nested begin/commit flushes once at outer commit', () {
      final emittedOperations = <Operation>[];
      final emittedChanges = <Change>[];
      var updateCount = 0;

      final manager = TransactionManager(
        flushWork: (work) {
          emittedOperations.addAll(work.operations);
          for (final applied in work.changes) {
            emittedChanges.addAll(applied.changes);
          }
          updateCount++;
        },
      )
        ..begin()
        ..begin();
      expect(manager.isInTransaction, isTrue);

      manager.requestUpdate();

      final dummyChange = changeAt(1);

      manager
        ..handleOperation(dummyOperation)
        ..handleAppliedChanges(batch([dummyChange], ChangeSource.created))

        // Inner commit should not flush
        ..commit();
      expect(emittedOperations, isEmpty);
      expect(emittedChanges, isEmpty);
      expect(updateCount, 0);

      // Outermost commit should flush once
      manager.commit();
      expect(emittedOperations.length, 1);
      expect(emittedChanges.length, 1);
      expect(updateCount, 1);
    });

    test('requestUpdate outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_) => updateCount++,
      ).requestUpdate();
      expect(updateCount, 1);
    });

    test('handleOperation outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_) => updateCount++,
      ).handleOperation(dummyOperation);
      expect(updateCount, 1);
    });

    test('handleChanges outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_) => updateCount++,
      ).handleAppliedChanges(
        batch([changeAt(1)], ChangeSource.created),
      );
      expect(updateCount, 1);
    });

    test('batches reach the flush in the order they were handed in', () {
      var flushed = <DocumentChangesApplied>[];

      final theirs = changeAt(1);
      final mine = changeAt(2);
      final theirsAgain = changeAt(3);

      final manager = TransactionManager(
        flushWork: (work) => flushed = work.changes,
      );

      manager.run(() {
        manager
          ..handleAppliedChanges(batch([theirs], ChangeSource.ingested))
          ..handleAppliedChanges(batch([mine], ChangeSource.created))
          ..handleAppliedChanges(batch([theirsAgain], ChangeSource.ingested));
      });

      // Three batches, not two merged by source: the manager keeps the order
      // the moves happened in and never groups them.
      expect(
        flushed.map((b) => b.source),
        [ChangeSource.ingested, ChangeSource.created, ChangeSource.ingested],
      );
      expect(
        flushed.expand((b) => b.changes),
        [theirs, mine, theirsAgain],
      );
    });

    test('commit outside transaction throws', () {
      expect(
        () => TransactionManager(
          flushWork: (_) {},
        ).commit(),
        throwsStateError,
      );
    });
  });
}
