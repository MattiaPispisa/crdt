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
  });
}
