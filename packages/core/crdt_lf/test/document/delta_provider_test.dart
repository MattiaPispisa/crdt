import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A text handler that counts how often the incremental path runs.
final class _CountingTextHandler extends CRDTTextHandler {
  _CountingTextHandler(super.doc, super.id);

  int folds = 0;

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
    DeltaSink<Object?>? sink,
  }) {
    folds++;
    return super.incrementCachedState(
      operation: operation,
      state: state,
      sink: sink,
    );
  }
}

/// A text handler that refuses to fold a remote change, loudly.
final class _ThrowingTextHandler extends CRDTTextHandler {
  _ThrowingTextHandler(super.doc, super.id);

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
    DeltaSink<Object?>? sink,
  }) =>
      throw StateError('this handler cannot fold anything');
}

/// A second document holding a counting text handler, already in step with
/// the given source document.
({CRDTDocument doc, _CountingTextHandler text}) _mirrorOf(
  CRDTDocument source,
) {
  final doc = CRDTDocument();
  final text = _CountingTextHandler(doc, 'text')
    ..useIncrementalCacheUpdate = true;
  doc.importChanges(source.exportChanges());
  // Warm the cache so the next import is queued instead of dropped.
  text
    ..value
    ..folds = 0;
  return (doc: doc, text: text);
}

void main() {
  group('cost when nobody watches', () {
    test('an imported change waits for a read', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');
      final mirror = _mirrorOf(source);

      sourceText.insert(5, '!');
      mirror.doc.importChanges(
        source.exportChanges(fromVersionVector: mirror.doc.getVersionVector()),
      );

      // Nothing decoded, nothing applied: the change only sits in the queue.
      expect(mirror.text.folds, 0);

      expect(mirror.text.value, 'hello!');
      expect(mirror.text.folds, 1);
    });

    test('a watched handler folds the change as it arrives', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');
      final mirror = _mirrorOf(source);

      final subscription = mirror.text.watch().listen((_) {});
      await _pump();
      mirror.text.folds = 0;

      sourceText.insert(5, '!');
      mirror.doc.importChanges(
        source.exportChanges(fromVersionVector: mirror.doc.getVersionVector()),
      );

      // Someone is listening, so the work happens now instead of at the next
      // read. It is the same work, at a different moment.
      expect(mirror.text.folds, 1);
      expect(mirror.text.value, 'hello!');
      expect(mirror.text.folds, 1);

      await subscription.cancel();
    });

    test('cancelling the last watcher goes back to waiting', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');
      final mirror = _mirrorOf(source);

      final subscription = mirror.text.watch().listen((_) {});
      await _pump();
      expect(mirror.text.hasDeltaListeners, isTrue);

      await subscription.cancel();
      expect(mirror.text.hasDeltaListeners, isFalse);

      mirror.text.value;
      mirror.text.folds = 0;

      sourceText.insert(5, '!');
      mirror.doc.importChanges(
        source.exportChanges(fromVersionVector: mirror.doc.getVersionVector()),
      );

      expect(mirror.text.folds, 0);
    });
  });

  group('the subscription', () {
    test('two watchers each start from an initial reset', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');

      final first = <HandlerUpdate<SequenceDelta<String>>>[];
      final second = <HandlerUpdate<SequenceDelta<String>>>[];
      final subscriptions = [
        text.watch().listen(first.add),
        text.watch().listen(second.add),
      ];
      await _pump();

      expect(first.single, isA<HandlerReset<SequenceDelta<String>>>());
      expect(second.single, isA<HandlerReset<SequenceDelta<String>>>());

      text.insert(1, 'b');
      await _pump();

      expect(first, hasLength(2));
      expect(second, hasLength(2));

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    test('the sequence number only ever grows', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      final seen = <int>[];
      final subscription = text.watch().listen((u) => seen.add(u.seq));
      await _pump();

      text
        ..insert(0, 'abc')
        ..invalidateCache()
        ..delete(0, 1);
      await _pump();

      expect(seen, orderedEquals([...seen]..sort()));
      expect(seen.toSet(), hasLength(seen.length));

      await subscription.cancel();
    });

    test('deltaSeq moves with a write, without reading the value', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      final subscription = text.watch().listen((_) {});
      await _pump();

      final before = text.deltaSeq;
      text.insert(0, 'abc');

      // The change published its event while it was being applied, so the
      // number already covers it — no read in between.
      expect(text.deltaSeq, greaterThan(before));
      expect(text.deltaSeq, text.readSynced().seq);

      await subscription.cancel();
    });

    test('deltaSeq is zero while nobody watches', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abc');

      expect(text.deltaSeq, 0);
    });

    test('readSynced reports the point its value reflects', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      final seen = <int>[];
      final subscription = text.watch().listen((u) => seen.add(u.seq));
      await _pump();

      text.insert(0, 'abc');
      await _pump();

      final point = text.readSynced();
      expect(point.value, 'abc');
      expect(point.seq, seen.last);

      await subscription.cancel();
    });

    test('a handler that throws does not hold the others back', () async {
      // The eager drain runs inside the loop over every handler. A throw that
      // escaped it would end that loop, and every handler after this one would
      // keep a version the document has already moved past.
      final source = CRDTDocument();
      final sourceBad = CRDTTextHandler(source, 'bad')..insert(0, 'hello');
      final sourceGood = CRDTTextHandler(source, 'good')..insert(0, 'world');

      final mirror = CRDTDocument();
      final bad = _ThrowingTextHandler(mirror, 'bad')
        ..useIncrementalCacheUpdate = true;
      final good = _CountingTextHandler(mirror, 'good')
        ..useIncrementalCacheUpdate = true;
      mirror.importChanges(source.exportChanges());
      // Warm both caches, so the next import is queued rather than dropped.
      bad.value;
      good
        ..value
        ..folds = 0;

      final causes = <ResetCause>[];
      final subscription = bad.watch().listen((update) {
        if (update is HandlerReset<SequenceDelta<String>>) {
          causes.add(update.cause);
        }
      });
      await _pump();

      sourceBad.insert(5, '!');
      sourceGood.insert(5, '!');
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      // The failing handler said why, and still reads correctly.
      expect(causes, [ResetCause.initial, ResetCause.applyFailed]);
      expect(bad.value, 'hello!');
      // The one after it got its change queued instead of being skipped, so
      // reading it folds that one change rather than replaying the history.
      expect(good.value, 'world!');
      expect(good.folds, 1);

      await subscription.cancel();
    });

    test('disposing the document ends the stream', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      var done = false;
      final subscription = text.watch().listen(
            (_) {},
            onDone: () => done = true,
          );
      await _pump();

      doc.dispose();
      await _pump();

      expect(done, isTrue);
      await subscription.cancel();
    });

    test('watching a disposed document says so instead of going quiet', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      doc.dispose();

      expect(text.watch, throwsA(isA<DocumentDisposedException>()));
    });
  });
}
