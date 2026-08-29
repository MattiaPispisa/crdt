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

    test('a change reaches its watchers before the write returns', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      final seen = <HandlerUpdate<SequenceDelta<String>>>[];
      final subscription = text.watch().listen(seen.add);
      await _pump();
      seen.clear();

      // No pump: the document hands its events out as it settles, so there is
      // no window where the change exists and a watcher still holds the old
      // value.
      text.insert(1, 'b');
      expect(seen, hasLength(1));

      final remote = CRDTDocument();
      CRDTTextHandler(remote, 'text');
      remote.importChanges(doc.exportChanges());
      (remote.registeredHandlers['text']! as CRDTTextHandler).insert(2, 'c');
      doc.importChanges(remote.exportChanges());
      expect(seen, hasLength(2));

      await subscription.cancel();
    });

    test('a watcher that writes back is served after it returns', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      final seen = <String>[];
      late StreamSubscription<HandlerUpdate<SequenceDelta<String>>>
          subscription;
      subscription = text.watch().listen((update) {
        seen.add(text.value);
        // One write only, or this recurses forever — which is the point: the
        // write is queued and handed out, not run inside this callback.
        if (text.value == 'ab') {
          text.insert(2, 'c');
        }
      });
      await _pump();
      seen.clear();

      text.insert(1, 'b');
      await _pump();

      expect(seen, ['ab', 'abc']);
      expect(text.value, 'abc');

      await subscription.cancel();
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

    test('readSynced hands back a value the caller owns', () async {
      // A handler that folds a change into its cached list in place would
      // otherwise hand out that list, and the consumer would find the next
      // change already inside the base it applies the delta to.
      final doc = CRDTDocument();
      final list = CRDTListHandler<String>(doc, 'list')..insert(0, 'a');

      final deltas = <SequenceDelta<String>>[];
      final subscription = list.watch().listen((update) {
        if (update is HandlerDelta<SequenceDelta<String>>) {
          deltas.add(update.delta);
        }
      });
      await _pump();

      final point = list.readSynced();
      expect(point.value, ['a']);

      list.insert(1, 'b');
      await _pump();

      // What the stream describes, folded onto what the read handed over.
      expect(deltas.length, 1);
      expect(list.applyDelta(point.value, deltas.single), list.value);

      await subscription.cancel();
    });

    test('applyDelta moves the value the way the handler does', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final list = CRDTListHandler<String>(doc, 'list');

      // The same delta shape over two value types: the text is moved by
      // [SequenceDelta.applyToText], the list by [SequenceDelta.apply]. Only
      // the handler knows which.
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(1),
        const SeqInsert<String>(['x']),
      ]);
      expect(text.applyDelta('ab', delta), 'axb');
      expect(list.applyDelta(['a', 'b'], delta), ['a', 'x', 'b']);
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

  // What lets a consumer that writes drop its own echo. `local` cannot: it
  // says which peer wrote the change, so two consumers on one document both
  // read `true` for each other's work.
  group('origin', () {
    /// Every delta event of [text], origin included.
    ({
      List<HandlerDelta<SequenceDelta<String>>> events,
      Future<void> Function() stop
    }) watchDeltas(CRDTTextHandler text) {
      // A handler with no cached state cannot advance one, so it answers a
      // write with a reset instead of a delta. One read warms it.
      text.value;
      final events = <HandlerDelta<SequenceDelta<String>>>[];
      final subscription = text.watch().listen((update) {
        if (update is HandlerDelta<SequenceDelta<String>>) {
          events.add(update);
        }
      });
      return (events: events, stop: subscription.cancel);
    }

    test('a local write reports the origin it was tagged with', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final watcher = watchDeltas(text);
      await _pump();

      final me = Object();
      doc.runInTransaction(() => text.insert(0, 'abc'), origin: me);
      await _pump();

      expect(watcher.events.single.origin, same(me));
      await watcher.stop();
    });

    test('an import reports the origin it was tagged with', () async {
      final source = CRDTDocument();
      CRDTTextHandler(source, 'text').insert(0, 'abc');

      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')
        ..useIncrementalCacheUpdate = true
        ..value;
      final watcher = watchDeltas(text);
      await _pump();

      final network = Object();
      doc.importChanges(source.exportChanges(), origin: network);
      await _pump();

      expect(watcher.events, isNotEmpty);
      expect(
        watcher.events.every((e) => identical(e.origin, network)),
        isTrue,
      );
      await watcher.stop();
    });

    test('an untagged write reports none', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final watcher = watchDeltas(text);
      await _pump();

      text.insert(0, 'abc');
      await _pump();

      expect(watcher.events.single.origin, isNull);
      await watcher.stop();
    });

    test('a nested write keeps the origin of the outer one', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final watcher = watchDeltas(text);
      await _pump();

      final me = Object();
      doc.runInTransaction(
        () => doc.runInTransaction(() => text.insert(0, 'abc')),
        origin: me,
      );
      await _pump();

      expect(watcher.events.single.origin, same(me));
      await watcher.stop();
    });

    test('the origin ends with the call that named it', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final watcher = watchDeltas(text);
      await _pump();

      doc.runInTransaction(() => text.insert(0, 'a'), origin: Object());
      text.insert(1, 'b');
      await _pump();

      expect(watcher.events, hasLength(2));
      expect(watcher.events.last.origin, isNull);
      await watcher.stop();
    });
  });
}
