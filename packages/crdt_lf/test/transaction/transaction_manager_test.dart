import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionManager', () {
    test('begin/commit defers and flushes updates and local changes', () {
      final emittedChanges = <Change>[];
      var updateCount = 0;

      final manager = TransactionManager(
        emitLocalChange: emittedChanges.add,
        emitUpdate: () => updateCount++,
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
      final dummyPeer = PeerId.generate();
      final dummyChange = Change(
        id: OperationId(dummyPeer, HybridLogicalClock(l: 1, c: 1)),
        deps: {},
        author: dummyPeer,
        operation: TestOperation('dummy'),
      );
      manager.handleLocalChange(dummyChange);
      expect(emittedChanges, isEmpty);
      expect(updateCount, 0);

      // Commit outermost transaction -> flush once
      manager.commit();
      expect(manager.isInTransaction, isFalse);
      expect(emittedChanges.length, 1);
      expect(updateCount, 1);
    });

    test('nested begin/commit flushes once at outer commit', () {
      final emittedChanges = <Change>[];
      var updateCount = 0;

      final manager = TransactionManager(
        emitLocalChange: emittedChanges.add,
        emitUpdate: () => updateCount++,
      )
        ..begin()
        ..begin();
      expect(manager.isInTransaction, isTrue);

      manager.requestUpdate();
      final dummyPeer = PeerId.generate();
      final dummyChange = Change(
        id: OperationId(dummyPeer, HybridLogicalClock(l: 2, c: 1)),
        deps: {},
        author: dummyPeer,
        operation: TestOperation('dummy'),
      );
      manager
        ..handleLocalChange(dummyChange)
        // Inner commit should not flush
        ..commit();
      expect(emittedChanges, isEmpty);
      expect(updateCount, 0);

      // Outermost commit should flush once
      manager.commit();
      expect(emittedChanges.length, 1);
      expect(updateCount, 1);
    });

    test('requestUpdate outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        emitLocalChange: (_) {},
        emitUpdate: () => updateCount++,
      ).requestUpdate();
      expect(updateCount, 1);
    });

    test('commit outside transaction throws', () {
      expect(
        () => TransactionManager(
          emitLocalChange: (_) {},
          emitUpdate: () {},
        ).commit(),
        throwsStateError,
      );
    });
  });
}

// Minimal Operation used by TransactionManager tests
class TestOperation extends Operation {
  TestOperation(String handlerId)
      : super(
          type: OperationType.fromPayload('Test:update'),
          id: handlerId,
        );
}
