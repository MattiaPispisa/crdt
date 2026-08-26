import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Lets the async delta stream deliver everything it holds.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A projection kept **only** from `readSynced()` and the deltas that follow.
///
/// It never reads `handler.value` on its own, which is the whole point: if it
/// still agrees with the handler, the deltas describe the state exactly.
class _Projection<V, D extends ComposableDelta<D>> {
  _Projection({
    required DeltaSyncPoint<V> Function() readSynced,
    required Stream<HandlerUpdate<D>> stream,
    required V Function(D delta, V base) applyDelta,
  })  : _readSynced = readSynced,
        _applyDelta = applyDelta {
    _subscription = stream.listen(_onUpdate);
  }

  final DeltaSyncPoint<V> Function() _readSynced;
  final V Function(D delta, V base) _applyDelta;
  late final StreamSubscription<HandlerUpdate<D>> _subscription;

  late V _value;
  int _seq = -1;

  /// Every event this projection saw, for tests that assert on the shape of
  /// the stream rather than on the value.
  final List<HandlerUpdate<D>> events = [];

  V get value => _value;

  int get resets =>
      events.whereType<HandlerReset<D>>().length;

  List<HandlerDelta<D>> get deltas =>
      events.whereType<HandlerDelta<D>>().toList();

  void _onUpdate(HandlerUpdate<D> update) {
    events.add(update);
    switch (update) {
      case HandlerReset<D>():
        final point = _readSynced();
        _value = point.value;
        _seq = point.seq;
      case HandlerDelta<D>():
        if (update.seq <= _seq) {
          // Already inside the value the last read handed over.
          return;
        }
        _value = _applyDelta(update.delta, _value);
        _seq = update.seq;
    }
  }

  Future<void> dispose() => _subscription.cancel();
}

_Projection<String, SequenceDelta<String>> _watchText(CRDTTextHandler text) =>
    _Projection<String, SequenceDelta<String>>(
      readSynced: text.readSynced,
      stream: text.watch(),
      applyDelta: (delta, base) => delta.applyToText(base),
    );

_Projection<List<T>, SequenceDelta<T>> _watchList<T>(
  CRDTListHandler<T> list,
) =>
    _Projection<List<T>, SequenceDelta<T>>(
      readSynced: () {
        final point = list.readSynced();
        // The handler hands back its own list; copy it so the projection
        // cannot drift by sharing the handler's state.
        return DeltaSyncPoint<List<T>>(
          value: List<T>.of(point.value),
          seq: point.seq,
        );
      },
      stream: list.watch(),
      applyDelta: (delta, base) => delta.apply(base),
    );

_Projection<String, SequenceDelta<String>> _watchFugueText(
  CRDTFugueTextHandler text,
) =>
    _Projection<String, SequenceDelta<String>>(
      readSynced: text.readSynced,
      stream: text.watch(),
      applyDelta: (delta, base) => delta.applyToText(base),
    );

_Projection<List<T>, SequenceDelta<T>> _watchFugueList<T>(
  CRDTFugueListHandler<T> list,
) =>
    _Projection<List<T>, SequenceDelta<T>>(
      readSynced: () {
        final point = list.readSynced();
        return DeltaSyncPoint<List<T>>(
          value: List<T>.of(point.value),
          seq: point.seq,
        );
      },
      stream: list.watch(),
      applyDelta: (delta, base) => delta.apply(base),
    );

_Projection<Map<String, T>, MapDelta<String, T>> _watchMap<T>(
  CRDTMapHandler<T> map,
) =>
    _Projection<Map<String, T>, MapDelta<String, T>>(
      readSynced: () {
        final point = map.readSynced();
        return DeltaSyncPoint<Map<String, T>>(
          value: Map<String, T>.of(point.value),
          seq: point.seq,
        );
      },
      stream: map.watch(),
      applyDelta: (delta, base) => delta.apply(base),
    );

void main() {
  group('watch', () {
    test('the first event is an initial reset', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');

      final projection = _watchText(text);
      await _pump();

      expect(projection.events, hasLength(1));
      expect(
        (projection.events.single as HandlerReset<SequenceDelta<String>>).cause,
        ResetCause.initial,
      );
      expect(projection.value, '');

      await projection.dispose();
    });

    test('nothing is emitted while nobody watches', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'hello');

      final projection = _watchText(text);
      await _pump();

      // The subscription starts from the value as it is now, not from a
      // replay of what happened before it existed.
      expect(projection.deltas, isEmpty);
      expect(projection.value, 'hello');

      await projection.dispose();
    });
  });

  group('CRDTTextHandler deltas', () {
    test('a local edit reaches the projection', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final projection = _watchText(text);
      await _pump();

      text.insert(0, 'hello');
      await _pump();

      expect(projection.deltas, hasLength(1));
      expect(projection.deltas.single.local, isTrue);
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('the event carries the id of the change that made it', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final projection = _watchText(text);
      await _pump();

      final changes = <Change>[];
      final subscription = doc.localChanges.listen(changes.add);

      text.insert(0, 'hi');
      await _pump();

      expect(projection.deltas.single.changeId, changes.single.id);
      expect(projection.deltas.single.author, changes.single.author);

      await subscription.cancel();
      await projection.dispose();
    });

    test('a compacted transaction produces one composed event', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final projection = _watchText(text);
      await _pump();

      doc.runInTransaction(() {
        text
          ..insert(0, 'ab')
          ..insert(2, 'cd');
      });
      await _pump();

      // Two contiguous inserts compound into one change, so the deltas of the
      // two operations arrive composed into one event.
      expect(projection.deltas, hasLength(1));
      expect(projection.value, 'abcd');
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('a transaction that cannot compact produces one event each',
        () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abcdef');
      final projection = _watchText(text);
      await _pump();

      doc.runInTransaction(() {
        text
          ..insert(0, 'X')
          ..delete(4, 1);
      });
      await _pump();

      expect(projection.deltas, hasLength(2));
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('non-BMP text survives the round trip', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final projection = _watchText(text);
      await _pump();

      text
        ..insert(0, '🌐ab')
        ..insert(1, '🌏')
        ..delete(0, 1)
        ..update(0, '😀');
      await _pump();

      expect(projection.value, text.value);
      expect(text.value, '😀ab');

      await projection.dispose();
    });

    test('an out-of-range edit reports the clamped effect', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abc');
      final projection = _watchText(text);
      await _pump();

      text
        // Past the end: appends.
        ..insert(99, 'Z')
        // Past the end: does nothing.
        ..delete(99, 3)
        // Longer than what is left: truncated.
        ..update(3, 'YYYY')
        // Past the end: does nothing.
        ..update(99, 'W');
      await _pump();

      expect(text.value, 'abcY');
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('a delta that moves nothing is still one event', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abc');
      final projection = _watchText(text);
      await _pump();

      text.delete(99, 1);
      await _pump();

      expect(projection.deltas, hasLength(1));
      expect(projection.deltas.single.delta.isEmpty, isTrue);
      expect(projection.value, 'abc');

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final projection = _watchText(text);
      await _pump();

      final random = Random(42);
      for (var round = 0; round < 200; round++) {
        final length = text.length;
        switch (random.nextInt(3)) {
          case 0:
            text.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              String.fromCharCode(97 + random.nextInt(26)),
            );
          case 1:
            if (length > 0) {
              final index = random.nextInt(length);
              text.delete(index, 1 + random.nextInt(length - index));
            }
          case 2:
            if (length > 0) {
              text.update(
                random.nextInt(length),
                String.fromCharCode(97 + random.nextInt(26)),
              );
            }
        }

        await _pump();
        expect(projection.value, text.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('CRDTListHandler deltas', () {
    test('insert, update and delete reach the projection', () async {
      final doc = CRDTDocument();
      final list = CRDTListHandler<String>(doc, 'list');
      final projection = _watchList(list);
      await _pump();

      list
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..update(0, 'A')
        ..delete(1, 1);
      await _pump();

      expect(list.value, ['A']);
      expect(projection.value, list.value);

      await projection.dispose();
    });

    test('an out-of-range operation reports the clamped effect', () async {
      final doc = CRDTDocument();
      final list = CRDTListHandler<String>(doc, 'list')..insert(0, 'a');
      final projection = _watchList(list);
      await _pump();

      list
        ..insert(99, 'z')
        ..delete(99, 2)
        ..update(99, 'w');
      await _pump();

      expect(list.value, ['a', 'z']);
      expect(projection.value, list.value);

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final list = CRDTListHandler<int>(doc, 'list');
      final projection = _watchList(list);
      await _pump();

      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final length = list.value.length;
        switch (random.nextInt(3)) {
          case 0:
            list.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              random.nextInt(1000),
            );
          case 1:
            if (length > 0) {
              final index = random.nextInt(length);
              list.delete(index, 1 + random.nextInt(length - index));
            }
          case 2:
            if (length > 0) {
              list.update(random.nextInt(length), random.nextInt(1000));
            }
        }

        await _pump();
        expect(projection.value, list.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('resets', () {
    test('dropping the cache asks for a fresh read', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abc');
      final projection = _watchText(text);
      await _pump();

      text.invalidateCache();
      await _pump();

      expect(projection.resets, 2);
      expect(
        projection.events.last,
        isA<HandlerReset<SequenceDelta<String>>>().having(
          (r) => r.cause,
          'cause',
          ResetCause.cacheDropped,
        ),
      );
      expect(projection.value, 'abc');

      await projection.dispose();
    });

    test('a snapshot import asks for a fresh read', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'abc');
      final projection = _watchText(text);
      await _pump();

      doc.importSnapshot(doc.takeSnapshot());
      await _pump();

      expect(
        projection.events.last,
        isA<HandlerReset<SequenceDelta<String>>>().having(
          (r) => r.cause,
          'cause',
          ResetCause.snapshotImport,
        ),
      );
      expect(projection.value, text.value);

      await projection.dispose();
    });
  });

  group('remote changes', () {
    test('an imported change arrives as a delta, not a reset', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');

      final mirror = CRDTDocument();
      final mirrorText = CRDTTextHandler(mirror, 'text');
      mirror.importChanges(source.exportChanges());

      final projection = _watchText(mirrorText);
      await _pump();

      sourceText.insert(5, ' world');
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      expect(projection.deltas, hasLength(1));
      expect(projection.deltas.single.local, isFalse);
      expect(projection.deltas.single.author, source.peerId);
      expect(projection.value, mirrorText.value);
      expect(mirrorText.value, sourceText.value);

      await projection.dispose();
    });

    test('the single-change path also publishes a delta', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');

      final mirror = CRDTDocument();
      final mirrorText = CRDTTextHandler(mirror, 'text');
      for (final change in source.exportChanges()) {
        mirror.applyChange(change);
      }

      final projection = _watchText(mirrorText);
      await _pump();

      sourceText.insert(5, '!');
      for (final change in source.exportChanges(
        fromVersionVector: mirror.getVersionVector(),
      )) {
        mirror.applyChange(change);
      }
      await _pump();

      expect(projection.deltas, hasLength(1));
      expect(projection.value, mirrorText.value);

      await projection.dispose();
    });

    test('a batch produces one event per change, in fold order', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'a');

      final mirror = CRDTDocument();
      final mirrorText = CRDTTextHandler(mirror, 'text');
      mirror.importChanges(source.exportChanges());

      final projection = _watchText(mirrorText);
      await _pump();

      sourceText
        ..insert(1, 'b')
        ..delete(0, 1)
        ..insert(1, 'c');
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      expect(projection.deltas, hasLength(3));
      expect(projection.value, mirrorText.value);

      await projection.dispose();
    });

    test('a change from the past drops the cache and asks for a read',
        () async {
      final peerA = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final peerB = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final textA = CRDTTextHandler(peerA, 'text');
      final textB = CRDTTextHandler(peerB, 'text');

      textA.insert(0, 'a');
      peerB.importChanges(peerA.exportChanges());

      final projection = _watchText(textB);
      await _pump();

      // Both write without seeing each other, then B receives A's change.
      // It sorts before what B already folded in, so B has to replay.
      textA.insert(1, 'A');
      textB.insert(1, 'B');
      peerB.importChanges(
        peerA.exportChanges(fromVersionVector: peerB.getVersionVector()),
      );
      await _pump();

      expect(
        projection.events.last,
        isA<HandlerReset<SequenceDelta<String>>>().having(
          (r) => r.cause,
          'cause',
          ResetCause.cacheDropped,
        ),
      );
      expect(projection.value, textB.value);

      await projection.dispose();
    });

    test('a read that beats the eager drain reports the deltas it lost',
        () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');

      final mirror = CRDTDocument();
      final mirrorText = CRDTTextHandler(mirror, 'text');
      mirror.importChanges(source.exportChanges());
      // Warm the cache so the next import is queued instead of dropped.
      expect(mirrorText.value, 'hello');

      // Nobody is watching yet, so the change only gets queued.
      sourceText.insert(5, '!');
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );

      // The subscription starts on a handler that still has work waiting; the
      // read it triggers folds that work in without collecting its deltas.
      final projection = _watchText(mirrorText);
      await _pump();

      expect(
        projection.events.map(
          (e) => e is HandlerReset<SequenceDelta<String>> ? e.cause : null,
        ),
        contains(ResetCause.deltasMissed),
      );
      expect(projection.value, mirrorText.value);
      expect(mirrorText.value, 'hello!');

      await projection.dispose();
    });

    test('turning the incremental path off asks for a read', () async {
      final source = CRDTDocument();
      final sourceText = CRDTTextHandler(source, 'text')..insert(0, 'hello');

      final mirror = CRDTDocument();
      final mirrorText = CRDTTextHandler(mirror, 'text');
      mirror.importChanges(source.exportChanges());

      final projection = _watchText(mirrorText);
      await _pump();

      mirrorText.useIncrementalCacheUpdate = false;
      sourceText.insert(5, '!');
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      expect(projection.deltas, isEmpty);
      expect(projection.resets, greaterThan(1));
      expect(projection.value, mirrorText.value);

      await projection.dispose();
    });

    test('two peers converge, each tracking its own projection', () async {
      final peerA = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final peerB = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final textA = CRDTTextHandler(peerA, 'text');
      final textB = CRDTTextHandler(peerB, 'text');

      final projectionA = _watchText(textA);
      final projectionB = _watchText(textB);
      await _pump();

      final random = Random(19);
      for (var round = 0; round < 30; round++) {
        for (final pair in [(peerA, textA), (peerB, textB)]) {
          final handler = pair.$2;
          final length = handler.length;
          if (length > 0 && random.nextBool()) {
            handler.delete(random.nextInt(length), 1);
          } else {
            handler.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              String.fromCharCode(97 + random.nextInt(26)),
            );
          }
        }

        peerB.importChanges(
          peerA.exportChanges(fromVersionVector: peerB.getVersionVector()),
        );
        peerA.importChanges(
          peerB.exportChanges(fromVersionVector: peerA.getVersionVector()),
        );

        await _pump();
        expect(projectionA.value, textA.value, reason: 'A, round $round');
        expect(projectionB.value, textB.value, reason: 'B, round $round');
      }

      expect(textA.value, textB.value);

      await projectionA.dispose();
      await projectionB.dispose();
    });
  });

  group('CRDTFugueTextHandler deltas', () {
    test('insert, delete and update reach the projection', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text');
      final projection = _watchFugueText(text);
      await _pump();

      text
        ..insert(0, 'hello')
        ..insert(5, ' world')
        ..delete(0, 1)
        ..update(0, 'E');
      await _pump();

      expect(text.value, 'Ello world');
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('a delete of several elements at once is one run', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'abcdef');
      final projection = _watchFugueText(text);
      await _pump();

      text.delete(1, 3);
      await _pump();

      expect(text.value, 'aef');
      expect(projection.value, text.value);
      expect(
        projection.deltas.single.delta.ops,
        [const SeqRetain<String>(1), const SeqDelete<String>(3)],
      );

      await projection.dispose();
    });

    test('an update that loses moves nothing', () async {
      final peerA = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final peerB = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final textA = CRDTFugueTextHandler(peerA, 'text')..insert(0, 'ab');
      final textB = CRDTFugueTextHandler(peerB, 'text');
      peerB.importChanges(peerA.exportChanges());

      final projection = _watchFugueText(textB);
      await _pump();

      // Both update the same element without seeing each other. The tree keeps
      // the winner, and only the winner can move anything a watcher sees.
      textA.update(0, 'A');
      textB.update(0, 'B');
      peerB.importChanges(
        peerA.exportChanges(fromVersionVector: peerB.getVersionVector()),
      );
      await _pump();

      expect(projection.value, textB.value);

      await projection.dispose();
    });

    test('non-BMP text survives the round trip', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text');
      final projection = _watchFugueText(text);
      await _pump();

      text
        ..insert(0, '🌐ab')
        ..insert(1, '🌏')
        ..delete(0, 1)
        ..update(0, '😀');
      await _pump();

      expect(text.value, '😀ab');
      expect(projection.value, text.value);

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text');
      final projection = _watchFugueText(text);
      await _pump();

      final random = Random(23);
      for (var round = 0; round < 150; round++) {
        final length = text.length;
        switch (random.nextInt(3)) {
          case 0:
            text.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              String.fromCharCode(97 + random.nextInt(26)),
            );
          case 1:
            if (length > 0) {
              final index = random.nextInt(length);
              text.delete(index, 1 + random.nextInt(length - index));
            }
          case 2:
            if (length > 0) {
              text.update(
                random.nextInt(length),
                String.fromCharCode(97 + random.nextInt(26)),
              );
            }
        }

        await _pump();
        expect(projection.value, text.value, reason: 'round $round');
      }

      await projection.dispose();
    });

    test('two peers converge, each tracking its own projection', () async {
      final peerA = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final peerB = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final textA = CRDTFugueTextHandler(peerA, 'text');
      final textB = CRDTFugueTextHandler(peerB, 'text');

      final projectionA = _watchFugueText(textA);
      final projectionB = _watchFugueText(textB);
      await _pump();

      final random = Random(31);
      for (var round = 0; round < 30; round++) {
        for (final handler in [textA, textB]) {
          final length = handler.length;
          if (length > 0 && random.nextBool()) {
            handler.delete(random.nextInt(length), 1);
          } else {
            handler.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              String.fromCharCode(97 + random.nextInt(26)),
            );
          }
        }

        peerB.importChanges(
          peerA.exportChanges(fromVersionVector: peerB.getVersionVector()),
        );
        peerA.importChanges(
          peerB.exportChanges(fromVersionVector: peerA.getVersionVector()),
        );

        await _pump();
        expect(projectionA.value, textA.value, reason: 'A, round $round');
        expect(projectionB.value, textB.value, reason: 'B, round $round');
      }

      expect(textA.value, textB.value);

      await projectionA.dispose();
      await projectionB.dispose();
    });
  });

  group('CRDTFugueListHandler deltas', () {
    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final list = CRDTFugueListHandler<int>(doc, 'list');
      final projection = _watchFugueList(list);
      await _pump();

      final random = Random(37);
      for (var round = 0; round < 150; round++) {
        final length = list.value.length;
        switch (random.nextInt(3)) {
          case 0:
            list.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              random.nextInt(1000),
            );
          case 1:
            if (length > 0) {
              final index = random.nextInt(length);
              list.delete(index, 1 + random.nextInt(length - index));
            }
          case 2:
            if (length > 0) {
              list.update(random.nextInt(length), random.nextInt(1000));
            }
        }

        await _pump();
        expect(projection.value, list.value, reason: 'round $round');
      }

      await projection.dispose();
    });

    test('a remote batch keeps the projection in step', () async {
      final source = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final sourceList = CRDTFugueListHandler<int>(source, 'list')
        ..insert(0, 1);

      final mirror = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final mirrorList = CRDTFugueListHandler<int>(mirror, 'list');
      mirror.importChanges(source.exportChanges());

      final projection = _watchFugueList(mirrorList);
      await _pump();

      sourceList
        ..insert(1, 2)
        ..insert(2, 3)
        ..delete(0, 1)
        ..update(0, 20);
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      expect(mirrorList.value, sourceList.value);
      expect(projection.value, mirrorList.value);

      await projection.dispose();
    });
  });

  group('CRDTMapHandler deltas', () {
    test('insert, update and delete carry the previous value', () async {
      final doc = CRDTDocument();
      final map = CRDTMapHandler<String>(doc, 'map');
      final projection = _watchMap(map);
      await _pump();

      map
        ..set('a', '1')
        ..update('a', '2')
        ..delete('a');
      await _pump();

      final events = projection.deltas.map((d) => d.delta).toList();
      expect(
        events[0].entries['a'],
        const MapEntrySet<String>(value: '1', previous: null),
      );
      expect(
        events[1].entries['a'],
        const MapEntrySet<String>(value: '2', previous: '1'),
      );
      expect(
        events[2].entries['a'],
        const MapEntryRemoved<String>(previous: '2'),
      );
      expect(projection.value, map.value);

      await projection.dispose();
    });

    test('an update of a key that is not there moves nothing', () async {
      final doc = CRDTDocument();
      final map = CRDTMapHandler<String>(doc, 'map');
      final projection = _watchMap(map);
      await _pump();

      map
        ..update('missing', 'x')
        ..delete('missing');
      await _pump();

      expect(projection.deltas, hasLength(2));
      expect(projection.deltas.every((d) => d.delta.isEmpty), isTrue);
      expect(projection.value, map.value);

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final map = CRDTMapHandler<int>(doc, 'map');
      final projection = _watchMap(map);
      await _pump();

      final random = Random(53);
      for (var round = 0; round < 150; round++) {
        final key = 'k${random.nextInt(6)}';
        switch (random.nextInt(3)) {
          case 0:
            map.set(key, random.nextInt(100));
          case 1:
            map.update(key, random.nextInt(100));
          case 2:
            map.delete(key);
        }

        await _pump();
        expect(projection.value, map.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('CRDTRegisterHandler deltas', () {
    test('a write reports both ends', () async {
      final doc = CRDTDocument();
      final register = CRDTRegisterHandler<String>(doc, 'reg')..set('one');
      final projection = _Projection<String?, RegisterDelta<String>>(
        readSynced: register.readSynced,
        stream: register.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      register.set('two');
      await _pump();

      expect(
        projection.deltas.single.delta,
        const RegisterDelta<String>(previous: 'one', current: 'two'),
      );
      expect(projection.value, register.value);

      await projection.dispose();
    });

    test('the first write of an empty register asks for a read', () async {
      final doc = CRDTDocument();
      final register = CRDTRegisterHandler<String>(doc, 'reg');
      final projection = _Projection<String?, RegisterDelta<String>>(
        readSynced: register.readSynced,
        stream: register.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      // Nothing is cached while the register holds nothing, so the write can
      // only be reported as "read me again".
      register.set('first');
      await _pump();

      expect(projection.value, 'first');
      expect(register.value, 'first');

      await projection.dispose();
    });
  });

  group('CRDTORSetHandler deltas', () {
    test('adding a value that is already in moves nothing', () async {
      final doc = CRDTDocument();
      final set = CRDTORSetHandler<String>(doc, 'set')..add('a');
      final projection = _Projection<Set<String>, SetDelta<String>>(
        readSynced: () {
          final point = set.readSynced();
          return DeltaSyncPoint<Set<String>>(
            value: Set<String>.of(point.value),
            seq: point.seq,
          );
        },
        stream: set.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      // A second add mints a new tag but the set anyone can see does not move.
      set.add('a');
      await _pump();

      expect(projection.deltas.single.delta.isEmpty, isTrue);
      expect(projection.value, set.value);

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final set = CRDTORSetHandler<String>(doc, 'set');
      final projection = _Projection<Set<String>, SetDelta<String>>(
        readSynced: () {
          final point = set.readSynced();
          return DeltaSyncPoint<Set<String>>(
            value: Set<String>.of(point.value),
            seq: point.seq,
          );
        },
        stream: set.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      final random = Random(61);
      for (var round = 0; round < 150; round++) {
        final value = 'v${random.nextInt(5)}';
        if (random.nextBool()) {
          set.add(value);
        } else {
          set.remove(value);
        }

        await _pump();
        expect(projection.value, set.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('CRDTORMapHandler deltas', () {
    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final map = CRDTORMapHandler<String, int>(doc, 'ormap');
      final projection = _Projection<Map<String, int>, MapDelta<String, int>>(
        readSynced: () {
          final point = map.readSynced();
          return DeltaSyncPoint<Map<String, int>>(
            value: Map<String, int>.of(point.value),
            seq: point.seq,
          );
        },
        stream: map.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      final random = Random(67);
      for (var round = 0; round < 150; round++) {
        final key = 'k${random.nextInt(5)}';
        if (random.nextBool()) {
          map.put(key, random.nextInt(100));
        } else {
          map.remove(key);
        }

        await _pump();
        expect(projection.value, map.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('CRDTFugueMovableListHandler deltas', () {
    test('a move keeps the element instead of rebuilding it', () async {
      final doc = CRDTDocument();
      final list = CRDTFugueMovableListHandler<String>(doc, 'movable')
        ..insertAll(0, ['a', 'b', 'c']);
      final projection = _Projection<List<String>, SequenceDelta<String>>(
        readSynced: () {
          final point = list.readSynced();
          return DeltaSyncPoint<List<String>>(
            value: List<String>.of(point.value),
            seq: point.seq,
          );
        },
        stream: list.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      list.move(0, 2);
      await _pump();

      expect(list.value, ['b', 'c', 'a']);
      expect(
        projection.deltas.single.delta.ops,
        [const SeqMove<String>(from: 0, to: 2)],
      );
      expect(projection.value, list.value);

      await projection.dispose();
    });

    test('the projection tracks a random edit stream', () async {
      final doc = CRDTDocument();
      final list = CRDTFugueMovableListHandler<int>(doc, 'movable');
      final projection = _Projection<List<int>, SequenceDelta<int>>(
        readSynced: () {
          final point = list.readSynced();
          return DeltaSyncPoint<List<int>>(
            value: List<int>.of(point.value),
            seq: point.seq,
          );
        },
        stream: list.watch(),
        applyDelta: (delta, base) => delta.apply(base),
      );
      await _pump();

      final random = Random(71);
      for (var round = 0; round < 150; round++) {
        final length = list.length;
        switch (random.nextInt(4)) {
          case 0:
            list.insert(
              length == 0 ? 0 : random.nextInt(length + 1),
              random.nextInt(1000),
            );
          case 1:
            if (length > 0) {
              list.delete(random.nextInt(length));
            }
          case 2:
            if (length > 0) {
              list.update(random.nextInt(length), random.nextInt(1000));
            }
          case 3:
            if (length > 1) {
              list.move(random.nextInt(length), random.nextInt(length));
            }
        }

        await _pump();
        expect(projection.value, list.value, reason: 'round $round');
      }

      await projection.dispose();
    });
  });

  group('the compaction invariant', () {
    // A transaction that compacts publishes the composition of the deltas of
    // the operations it fused. A peer that receives the compacted change
    // publishes the delta of that one operation. The two must agree, or the
    // same change would describe two different edits.
    Future<void> expectSameDelta(
      void Function(CRDTTextHandler text) edit, {
      required String seed,
    }) async {
      final source = CRDTDocument(peerId: PeerId.parse(_peerIdA));
      final sourceText = CRDTTextHandler(source, 'text');
      if (seed.isNotEmpty) {
        sourceText.insert(0, seed);
      }

      final mirror = CRDTDocument(peerId: PeerId.parse(_peerIdB));
      final mirrorText = CRDTTextHandler(mirror, 'text');
      mirror.importChanges(source.exportChanges());

      final local = _watchText(sourceText);
      final remote = _watchText(mirrorText);
      await _pump();

      source.runInTransaction(() => edit(sourceText));
      mirror.importChanges(
        source.exportChanges(fromVersionVector: mirror.getVersionVector()),
      );
      await _pump();

      expect(
        remote.deltas.map((d) => d.delta),
        local.deltas.map((d) => d.delta),
        reason: 'the composed local delta must equal the compacted one',
      );
      expect(mirrorText.value, sourceText.value);

      await local.dispose();
      await remote.dispose();
    }

    test('contiguous inserts', () async {
      await expectSameDelta(
        seed: '',
        (text) => text
          ..insert(0, 'ab')
          ..insert(2, 'cd'),
      );
    });

    test('an insert then a delete of part of it', () async {
      await expectSameDelta(
        seed: 'xy',
        (text) => text
          ..insert(2, 'abc')
          ..delete(3, 1),
      );
    });

    test('a forward delete run', () async {
      await expectSameDelta(
        seed: 'abcdef',
        (text) => text
          ..delete(1, 1)
          ..delete(1, 1),
      );
    });

    test('a backward delete run', () async {
      await expectSameDelta(
        seed: 'abcdef',
        (text) => text
          ..delete(3, 1)
          ..delete(2, 1),
      );
    });

    test('two updates at the same index', () async {
      await expectSameDelta(
        seed: 'abcdef',
        (text) => text
          ..update(1, 'X')
          ..update(1, 'Y'),
      );
    });

    test('an insert then an update over it', () async {
      await expectSameDelta(
        seed: 'abc',
        (text) => text
          ..insert(1, 'ZZ')
          ..update(1, 'Q'),
      );
    });
  });
}

// The replay order breaks ties on the peer id, so a test that asserts an exact
// merged value has to pin them.
const _peerIdA = '00000000-0000-4000-8000-00000000000a';
const _peerIdB = '00000000-0000-4000-8000-00000000000b';
