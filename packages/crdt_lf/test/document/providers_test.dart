import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('handler cache', () {
    late CRDTDocument doc;
    late PeerId author;

    setUp(() {
      author = PeerId.generate();
      doc = CRDTDocument(peerId: author);
    });

    test('default incrementCachedState invalidates cache', () {
      final freshDoc = CRDTDocument();
      final freshHandler = TestHandler(freshDoc)..updateCachedState('primed');
      expect(freshHandler.cachedState, isNotNull);
      freshDoc.registerOperation(TestOperation.fromHandler(freshHandler));
      expect(freshHandler.cachedState, isNull);
    });

    test('should not increment cached without a cached state', () {
      final handler = _FakeCRDTListHandler(doc, 'test-list');
      expect(handler._incrementedCount, 0);
      // cached state is never computed
      handler.insert(0, 'Hello');
      expect(handler._incrementedCount, 0);
    });

    test('should increment cached state on operation application', () {
      final handler = _FakeCRDTListHandler(doc, 'test-list');
      expect(handler._incrementedCount, 0);
      // compute cached state
      expect(handler.value, const <String>[]);
      handler
        ..insert(0, 'Hello')
        ..insert(1, 'World');
      expect(handler._incrementedCount, 2);
    });

    test(
        'should not increment cached state'
        ' if useIncrementalCacheUpdate is false', () {
      final handler = _FakeCRDTListHandler(doc, 'test-list')
        ..useIncrementalCacheUpdate = false;
      expect(handler._incrementedCount, 0);
      expect(handler.value, const <String>[]);
      handler.insert(0, 'Hello');
      expect(handler._incrementedCount, 0);
    });

    test('should remove cache if incrementalCache return null', () {
      final handler = _FakeCRDTListHandler(doc, 'test-list')
        ..useIncrementalCacheUpdate = true
        ..value;
      expect(handler._incrementedCount, 0);
      expect(handler.value, const <String>[]);

      handler.insert(0, 'Hello');
      expect(handler._incrementedCount, 1);

      handler
        ..notIncrementState = true
        // this insert will not increment the cached state
        ..insert(1, 'Dart')
        // increment state not called
        ..insert(2, 'Flutter');
      expect(handler._incrementedCount, 2);
    });

    test('should ignore old cached state', () {
      final handler = _FakeCRDTListHandler(doc, 'test-list')
        ..useIncrementalCacheUpdate = true;
      expect(handler._incrementedCount, 0);
      expect(handler.value, const <String>[]);
      handler.insert(0, 'Hello');
      expect(handler._incrementedCount, 1);
      handler
        ..useIncrementalCacheUpdate = false
        ..insert(1, 'World');
      expect(handler._incrementedCount, 1);

      // previous "insert" didn't increment cached state
      // therefore, new "insert" should not increment cached state
      handler
        ..useIncrementalCacheUpdate = true
        ..insert(2, 'Dart!');
      expect(handler._incrementedCount, 1);
      expect(handler.value, ['Hello', 'World', 'Dart!']);
    });

    test(
        'should related external handler changes '
        'invalidate the handlers cache', () {
      final handler1 = _FakeCRDTListHandler(doc, 'error-handler-1')
        ..useIncrementalCacheUpdate = true
        ..value;
      final handler2 = _FakeCRDTListHandler(doc, 'error-handler-2')
        ..useIncrementalCacheUpdate = true
        ..value;

      final otherDoc = CRDTDocument(peerId: PeerId.generate());
      final otherHandler = _FakeCRDTListHandler(otherDoc, 'error-handler-1')
        ..useIncrementalCacheUpdate = true
        ..value;

      // Initial state
      expect(handler1._incrementedCount, 0);
      expect(handler2._incrementedCount, 0);

      // Perform operations that will succeed
      handler1.insert(0, 'Hello'); // cache incremented
      handler2.insert(0, 'World'); // cache incremented
      otherHandler.insert(0, 'Other');
      expect(handler1._incrementedCount, 1);
      expect(handler2._incrementedCount, 1);

      doc.runInTransaction<void>(() {
        handler1.insert(1, 'Dart'); // cache incremented

        // contains changes for handler1 so it's cache is invalidated
        doc.importChanges(otherDoc.exportChanges());

        handler2.insert(1, 'Flutter'); // cache incremented
      });

      handler1.insert(2, 'Test'); // cache not incremented
      handler2.insert(2, 'Test2'); // cache incremented

      // Cache should be invalidated, so incremental count should not increase
      expect(handler1._incrementedCount, 2);
      // value is computed from scratch
      expect(
        handler1.value,
        containsAll(
          ['Other', 'Dart', 'Test', 'Hello'],
        ),
      );
      expect(handler2._incrementedCount, 3);
    });

    test(
        'should external actions not applied to document '
        'not affect the handlers cache', () {
      final handler1 = _FakeCRDTListHandler(doc, 'external-handler-1')
        ..useIncrementalCacheUpdate = true
        ..value;
      final handler2 = _FakeCRDTListHandler(doc, 'external-handler-2')
        ..useIncrementalCacheUpdate = true
        ..value;

      // Initial state
      expect(handler1._incrementedCount, 0);
      expect(handler2._incrementedCount, 0);

      // Perform initial operations
      handler1.insert(0, 'Hello'); // cache incremented
      handler2.insert(0, 'World');
      expect(handler1._incrementedCount, 1);
      expect(handler2._incrementedCount, 1);

      // Import external changes in a transaction
      expect(
        () => doc.runInTransaction<void>(() {
          // Perform local operations
          handler1.insert(1, 'Dart'); // cache incremented
          handler2.insert(1, 'Flutter');

          final unexpectedDep = OperationId(
            PeerId.generate(),
            HybridLogicalClock(l: 9999999, c: 9999999),
          );
          doc.applyChange(
            Change(
              author: author,
              id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
              operation: TestOperation.fromHandler(handler1),
              deps: {unexpectedDep},
            ),
          ); // throws an exception unrelated to handlers
        }),
        throwsA(isA<CrdtException>()),
      );

      handler1.insert(2, 'Test1'); // cache incremented
      handler2.insert(2, 'Test2'); // cache incremented

      expect(handler1._incrementedCount, 3);
      expect(handler2._incrementedCount, 3);
      expect(handler1.value, containsAll(['Hello', 'Dart', 'Test1']));
    });
  });

  group('remote changes and the handler cache', () {
    late CRDTDocument source;
    late CRDTFugueTextHandler sourceText;
    late CRDTDocument target;
    late CRDTFugueTextHandler targetText;

    setUp(() {
      source = CRDTDocument(peerId: PeerId.generate());
      sourceText = CRDTFugueTextHandler(source, 'fugue');
      target = CRDTDocument(peerId: PeerId.generate());
      targetText = CRDTFugueTextHandler(target, 'fugue');

      sourceText.insert(0, 'hello');
      target.importChanges(source.exportChanges());
      // Warm the cache: a handler with nothing cached has nothing to advance.
      expect(targetText.value, 'hello');
    });

    test('a Fugue handler keeps its cached state', () {
      sourceText.insert(5, ' world');
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );

      expect(targetText.cachedState, isNotNull);
      expect(targetText.value, 'hello world');
    });

    test('an in-order change keeps the cache of any handler', () {
      // This handler resolves conflicts by replay order, so it can only take
      // the change because the change is the newest one.
      final sourcePlain = CRDTTextHandler(source, 'plain')..insert(0, 'hi');
      final targetPlain = CRDTTextHandler(target, 'plain');
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );
      expect(targetPlain.value, 'hi');

      sourcePlain.insert(2, '!');
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );

      expect(targetPlain.cachedState, isNotNull);
      expect(targetPlain.value, 'hi!');
    });

    test('a change from the past drops the cache of a replay-order handler',
        () {
      // A clock ahead of the wall clock, so every change [ahead] makes is
      // newer than anything [behind] can produce.
      final ahead = CRDTDocument(
        peerId: PeerId.generate(),
        initialClock: HybridLogicalClock(
          l: DateTime.now().millisecondsSinceEpoch + 60000,
          c: 0,
        ),
      );
      final aheadText = CRDTTextHandler(ahead, 'plain')..insert(0, 'ahead');
      expect(aheadText.value, 'ahead');

      final behind = CRDTDocument(peerId: PeerId.generate());
      CRDTTextHandler(behind, 'plain').insert(0, 'behind');

      ahead.importChanges(behind.exportChanges());

      expect(aheadText.cachedState, isNull);
      // The recompute replays both changes in clock order, so the older one
      // lands first.
      expect(aheadText.value, 'aheadbehind');
    });

    test('a Fugue handler takes a change from the past anyway', () {
      final ahead = CRDTDocument(
        peerId: PeerId.generate(),
        initialClock: HybridLogicalClock(
          l: DateTime.now().millisecondsSinceEpoch + 60000,
          c: 0,
        ),
      );
      final aheadText = CRDTFugueTextHandler(ahead, 'fugue')..insert(0, 'a');
      expect(aheadText.value, 'a');

      final behind = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(behind, 'fugue').insert(0, 'b');

      ahead.importChanges(behind.exportChanges());

      expect(aheadText.cachedState, isNotNull);
      expect(aheadText.value.length, 2);
    });

    test('the handler revision advances on a queued change', () {
      final before = target.revisionForHandler('fugue');

      sourceText.insert(5, '!');
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );

      expect(target.revisionForHandler('fugue'), greaterThan(before));
    });

    test('a batch too big to queue falls back to a full recompute', () {
      for (var i = 0; i < 300; i += 1) {
        sourceText.insert(sourceText.length, 'x');
      }
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );

      expect(targetText.cachedState, isNull);
      expect(targetText.value, sourceText.value);
    });

    test('a change that cannot be applied falls back to a full recompute', () {
      final other = CRDTDocument(peerId: PeerId.generate());
      final otherText = _UnappliableFugueText(other, 'fugue');
      other.importChanges(source.exportChanges());
      expect(otherText.value, 'hello');

      sourceText.insert(5, ' world');
      other.importChanges(
        source.exportChanges(fromVersionVector: other.getVersionVector()),
      );

      expect(otherText.value, 'hello world');
    });

    test('a change for another handler type is skipped by both paths', () {
      // The batch import groups changes by handler id alone, so a change can
      // reach a handler that is not the one that wrote it.
      final other = CRDTDocument(peerId: PeerId.generate());
      final otherText = _ForeignTypeFugueText(other, 'fugue');
      // Warm the cache: a handler with nothing cached has nothing to advance.
      expect(otherText.value, '');

      other.importChanges(source.exportChanges());

      expect(otherText.cachedState, isNull, reason: 'the queue gave up');
      // The recompute reads the change through the same path, so it skips it
      // too: folding and replaying still agree.
      expect(otherText.value, '');
    });

    test('a snapshot folds a queued change before storing it', () {
      sourceText.insert(5, ' world');
      // Nothing reads the handler, so the change is still waiting in the queue
      // when the snapshot asks for its state.
      target.importChanges(
        source.exportChanges(fromVersionVector: target.getVersionVector()),
      );
      final snapshot = target.takeSnapshot();

      final restored = CRDTDocument(peerId: PeerId.generate());
      final restoredText = CRDTFugueTextHandler(restored, 'fugue');
      restored.importSnapshot(snapshot);

      expect(restoredText.value, 'hello world');
      expect(targetText.value, 'hello world');
    });

    test('a snapshot that covers a queued change replaces it', () {
      sourceText.insert(5, '!');
      target
        ..importChanges(
          source.exportChanges(fromVersionVector: target.getVersionVector()),
        )
        // The snapshot already contains what waits in the queue.
        ..importSnapshot(source.takeSnapshot(pruneHistory: false));

      expect(targetText.cachedState, isNull);
      expect(targetText.value, 'hello!');
    });

    test('the queue takes exactly _maxPendingRemoteChanges changes', () {
      // The bound lives in the library; 256 is the value it is set to.
      for (var i = 0; i < 256; i += 1) {
        sourceText.insert(sourceText.length, 'x');
        for (final change in source
            .exportChanges(fromVersionVector: target.getVersionVector())
            .sorted()) {
          target.applyChange(change);
        }
      }

      expect(targetText.cachedState, isNotNull);
      expect(targetText.value, sourceText.value);

      for (var i = 0; i < 257; i += 1) {
        sourceText.insert(sourceText.length, 'y');
        for (final change in source
            .exportChanges(fromVersionVector: target.getVersionVector())
            .sorted()) {
          target.applyChange(change);
        }
      }

      expect(targetText.cachedState, isNull);
      expect(targetText.value, sourceText.value);
    });

    test('turning the incremental path off drops a pending queue', () {
      final other = CRDTDocument(peerId: PeerId.generate());
      final otherList = _CountingListHandler(other, 'list')..insert(0, 'a');
      final receiver = CRDTDocument(peerId: PeerId.generate());
      final receiverList = _CountingListHandler(receiver, 'list');
      receiver.importChanges(other.exportChanges());
      expect(receiverList.value, ['a']);
      expect(receiverList.increments, 0);

      otherList.insert(1, 'b');
      receiver.importChanges(
        other.exportChanges(fromVersionVector: receiver.getVersionVector()),
      );

      // The change is already queued. Reading it now must replay the history
      // instead of folding, because folding is what the flag turns off.
      receiverList.useIncrementalCacheUpdate = false;
      expect(receiverList.value, ['a', 'b']);
      expect(receiverList.increments, 0);
    });

    // The drain empties the queue and the version is already pinned past those
    // changes, so a throw halfway through used to leave the old state in place:
    // one loud read, then quiet wrong answers for ever. Both reads must fail.
    test('a change the queue cannot decode keeps failing, not just once', () {
      final author = PeerId.generate();
      target.applyChange(
        Change.fromPayloadBytes(
          id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
          deps: {},
          author: author,
          payloadBytes: OperationEnvelopeCodec.encode(
            handlerType: targetText.handlerType,
            handlerId: targetText.id,
            kind: 99,
            body: Uint8List(0),
          ),
        ),
      );

      expect(
        () => targetText.value,
        throwsA(isA<UnknownOperationKindException>()),
      );
      expect(targetText.cachedState, isNull);
      expect(
        () => targetText.value,
        throwsA(isA<UnknownOperationKindException>()),
      );
    });
  });

  group('the replay boundary', () {
    test('a change from the past is folded onto a pruned history', () {
      final ahead = CRDTDocument(peerId: PeerId.generate());
      final aheadText = CRDTTextHandler(ahead, 'text')..insert(0, 'aaa');
      expect(aheadText.value, 'aaa');

      final behind = CRDTDocument(peerId: PeerId.generate());
      CRDTTextHandler(behind, 'text').insert(0, 'bbb');

      // A twin seeded with the same snapshot, but never folding anything.
      final twin = CRDTDocument(peerId: PeerId.generate());
      final twinText = CRDTTextHandler(twin, 'text')
        ..useIncrementalCacheUpdate = false;
      twin.importSnapshot(ahead.takeSnapshot(pruneHistory: false));
      expect(twinText.value, 'aaa');

      // After the prune the history is empty, so a recompute replays nothing
      // and the boundary becomes "no change at all".
      ahead.takeSnapshot();
      expect(aheadText.value, 'aaa');

      ahead.importChanges(behind.exportChanges());
      twin.importChanges(behind.exportChanges());

      // The change is older than what the snapshot holds, yet the snapshot is
      // all the history left: folding it is what replaying it would do too.
      expect(aheadText.cachedState, isNotNull);
      final folded = aheadText.value;
      aheadText.invalidateCache();
      expect(aheadText.value, folded);
      expect(twinText.value, folded);
    });

    test('a change imported mid transaction drops a replay-order cache', () {
      final other = CRDTDocument(peerId: PeerId.generate());
      CRDTTextHandler(other, 'text').insert(0, 'X');

      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTTextHandler(doc, 'text');
      expect(text.value, '');

      doc.runInTransaction(() {
        // Folded into the state, but the change that carries it — and its
        // clock — only exists on commit, so the boundary says nothing.
        text.insert(0, 'local');
        doc.importChanges(other.exportChanges());
      });

      expect(text.cachedState, isNull);
      final folded = text.value;
      text.invalidateCache();
      expect(text.value, folded);
    });

    test('a change imported mid transaction keeps a commutative cache', () {
      final other = CRDTDocument(peerId: PeerId.generate());
      final otherText = CRDTFugueTextHandler(other, 'fugue')..insert(0, 'X');

      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'fugue');
      expect(text.value, '');

      doc.runInTransaction(() {
        text.insert(0, 'local');
        doc.importChanges(other.exportChanges());
      });

      expect(text.cachedState, isNotNull);
      final folded = text.value;
      text.invalidateCache();
      expect(text.value, folded);

      // The boundary is usable again once the transaction has committed.
      otherText.insert(1, 'Y');
      doc.importChanges(
        other.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      final next = text.value;
      text.invalidateCache();
      expect(text.value, next);
    });
  });
}

/// A Fugue text handler that never advances its state, to exercise the fallback
/// to a full recompute.
///
/// Draining the queue gives up the same way whether the change cannot be
/// decoded or the operation cannot be applied: it drops the cache and lets the
/// next read replay the history.
class _UnappliableFugueText extends CRDTFugueTextHandler {
  _UnappliableFugueText(super.doc, super.id);

  @override
  FugueTextState? incrementCachedState({
    required Operation operation,
    required FugueTextState state,
  }) =>
      null;
}

/// A Fugue text handler under a type tag of its own.
///
/// A change written by the ordinary handler carries the same id, so the batch
/// import routes it here, and a different type tag, so this handler declines
/// it.
class _ForeignTypeFugueText extends CRDTFugueTextHandler {
  _ForeignTypeFugueText(super.doc, super.id);

  @override
  String get handlerType => 'SomeOtherFugueText';
}

/// Counts how many times the cached state is advanced by one operation.
class _CountingListHandler extends CRDTListHandler<String> {
  _CountingListHandler(super.doc, super.id);

  int increments = 0;

  @override
  List<String>? incrementCachedState({
    required Operation operation,
    required List<String> state,
  }) {
    increments += 1;
    return super.incrementCachedState(operation: operation, state: state);
  }
}

class _FakeCRDTListHandler extends CRDTListHandler<String> {
  _FakeCRDTListHandler(super.doc, super.id);

  /// count of `incrementCachedState`
  var _incrementedCount = 0;

  /// `incrementCachedState` will return null
  bool notIncrementState = false;

  @override
  List<String>? incrementCachedState({
    required Operation operation,
    required List<String> state,
  }) {
    _incrementedCount++;

    if (notIncrementState) {
      return null;
    }

    return super.incrementCachedState(operation: operation, state: state);
  }
}
