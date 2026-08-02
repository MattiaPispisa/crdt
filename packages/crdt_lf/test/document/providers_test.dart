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
