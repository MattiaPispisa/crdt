import 'dart:math';

import 'package:crdt_lf/src/algorithm/sqrt_decomposition/sqrt_decomposition.dart';
import 'package:test/test.dart';

/// One run as the index and the model both describe it.
typedef _Run<T> = ({T key, int liveOffset});

/// A trivial reference model: a plain ordered list of `(key, length,
/// liveLength)` triples.
///
/// Every public query of [SqrtDecomposition] is mirrored here with an obvious
/// `O(n)` implementation; the randomized test asserts the two agree.
class _Model<T> {
  final List<T> keys = [];
  final List<int> lengths = [];
  final List<int> liveLengths = [];

  void insertAfter(
    T predecessor,
    T key, {
    required int length,
    required int liveLength,
  }) {
    final at = keys.indexOf(predecessor) + 1;
    keys.insert(at, key);
    lengths.insert(at, length);
    liveLengths.insert(at, liveLength);
  }

  void insertAtFront(T key, {required int length, required int liveLength}) {
    keys.insert(0, key);
    lengths.insert(0, length);
    liveLengths.insert(0, liveLength);
  }

  void setLengths(T key, {required int length, required int liveLength}) {
    final at = keys.indexOf(key);
    lengths[at] = length;
    liveLengths[at] = liveLength;
  }

  int lengthOf(T key) {
    final at = keys.indexOf(key);
    return at == -1 ? -1 : lengths[at];
  }

  int liveLengthOf(T key) {
    final at = keys.indexOf(key);
    return at == -1 ? -1 : liveLengths[at];
  }

  _Run<T>? liveAt(int position) {
    if (position < 0) {
      return null;
    }
    var remaining = position;
    for (var i = 0; i < keys.length; i++) {
      if (remaining < liveLengths[i]) {
        return (key: keys[i], liveOffset: remaining);
      }
      remaining -= liveLengths[i];
    }
    return null;
  }

  int liveRankOfRunStart(T key) {
    final at = keys.indexOf(key);
    if (at == -1) {
      return -1;
    }
    var rank = 0;
    for (var i = 0; i < at; i++) {
      rank += liveLengths[i];
    }
    return rank;
  }

  List<_Run<T>> runsFromLive(int position, int limit) {
    final out = <_Run<T>>[];
    if (position < 0 || limit <= 0) {
      return out;
    }
    var remaining = position;
    var started = false;
    for (var i = 0; i < keys.length; i++) {
      if (!started) {
        if (remaining >= liveLengths[i]) {
          remaining -= liveLengths[i];
          continue;
        }
        started = true;
        out.add((key: keys[i], liveOffset: remaining));
      } else {
        out.add((key: keys[i], liveOffset: 0));
      }
      if (out.length == limit) {
        break;
      }
    }
    return out;
  }

  T? predecessorOf(T key) {
    final at = keys.indexOf(key);
    if (at <= 0) {
      return null;
    }
    return keys[at - 1];
  }

  T? successorOf(T key) {
    final at = keys.indexOf(key);
    if (at == -1 || at == keys.length - 1) {
      return null;
    }
    return keys[at + 1];
  }

  T? first() => keys.isEmpty ? null : keys.first;

  T? last() => keys.isEmpty ? null : keys.last;

  int get total => lengths.fold(0, (a, b) => a + b);

  int get liveTotal => liveLengths.fold(0, (a, b) => a + b);
}

/// [SqrtDecomposition.forEachRunFromLive] collected into a list of at most
/// [limit] runs.
List<_Run<T>> _runsFrom<T>(
  SqrtDecomposition<T> index,
  int position,
  int limit,
) {
  final out = <_Run<T>>[];
  if (limit <= 0) {
    return out;
  }
  index.forEachRunFromLive(position, (key, length, liveLength, liveOffset) {
    out.add((key: key, liveOffset: liveOffset));
    return out.length < limit;
  });
  return out;
}

/// An index of single-element keys `0 … count - 1`, all live.
SqrtDecomposition<int> _singles(int count) {
  final index = SqrtDecomposition<int>()
    ..insertAtFront(0, length: 1, liveLength: 1);
  for (var key = 1; key < count; key++) {
    index.insertAfter(key - 1, key, length: 1, liveLength: 1);
  }
  return index;
}

void main() {
  group('SqrtDecomposition', () {
    test('empty index', () {
      final index = SqrtDecomposition<int>();
      expect(index.length, 0);
      expect(index.runCount, 0);
      expect(index.liveLength, 0);
      expect(index.liveAt(0), isNull);
      expect(index.liveAt(-1), isNull);
      expect(index.first(), isNull);
      expect(index.last(), isNull);
      expect(index.predecessorOf(1), isNull);
      expect(index.successorOf(1), isNull);
      expect(index.liveRankOfRunStart(1), -1);
      expect(index.lengthOf(1), -1);
      expect(index.liveLengthOf(1), -1);
      expect(index.contains(1), isFalse);
    });

    test('insertAtFront builds a reversed sequence', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(3, length: 1, liveLength: 1)
        ..insertAtFront(2, length: 1, liveLength: 1)
        ..insertAtFront(1, length: 1, liveLength: 1);

      expect(index.length, 3);
      expect(index.liveAt(0), (key: 1, liveOffset: 0));
      expect(index.liveAt(1), (key: 2, liveOffset: 0));
      expect(index.liveAt(2), (key: 3, liveOffset: 0));
      expect(index.liveAt(3), isNull);
      expect(index.last(), 3);
    });

    test('insertAfter places keys in order', () {
      final index = _singles(3)
        ..insertAfter(0, 5, length: 1, liveLength: 1); // between 0 and 1

      expect(
        [for (var i = 0; i < index.length; i++) index.liveAt(i)!.key],
        [0, 5, 1, 2],
      );
      expect(index.first(), 0);
      expect(index.successorOf(0), 5);
      expect(index.successorOf(5), 1);
      expect(index.successorOf(2), isNull);
      expect(index.predecessorOf(5), 0);
      expect(index.predecessorOf(1), 5);
      expect(index.predecessorOf(0), isNull);
      expect(index.liveRankOfRunStart(2), 3);
      expect(index.liveRankOfRunStart(0), 0);
    });

    test('a key taken out of the live order keeps its slot', () {
      final index = _singles(3)..setLengths(1, length: 1, liveLength: 0);

      expect(index.liveAt(0), (key: 0, liveOffset: 0));
      expect(index.liveAt(1), (key: 2, liveOffset: 0)); // 1 is skipped
      expect(index.liveAt(2), isNull);
      // The tombstone keeps its slot, so neighbours still resolve.
      expect(index.predecessorOf(2), 1);
      // Ranks count only live elements.
      expect(index.liveRankOfRunStart(2), 1);

      index.setLengths(1, length: 1, liveLength: 1);
      expect(index.liveAt(1), (key: 1, liveOffset: 0));
      expect(index.liveRankOfRunStart(2), 2);
    });

    test('inserting a dead key keeps order but not the live count', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(1, length: 1, liveLength: 1)
        ..insertAfter(1, 2, length: 1, liveLength: 0) // dead
        ..insertAfter(2, 3, length: 1, liveLength: 1);

      expect(index.length, 3);
      expect(index.liveLength, 2);
      expect(index.liveAt(0), (key: 1, liveOffset: 0));
      expect(index.liveAt(1), (key: 3, liveOffset: 0));
      expect(index.predecessorOf(3), 2);
    });

    group('runs of more than one element', () {
      // Three runs: a=4 elements (3 live), b=1 (1 live), c=5 (0 live).
      SqrtDecomposition<String> seeded() {
        return SqrtDecomposition<String>()
          ..insertAtFront('a', length: 4, liveLength: 3)
          ..insertAfter('a', 'b', length: 1, liveLength: 1)
          ..insertAfter('b', 'c', length: 5, liveLength: 0);
      }

      test('lengths add up across runs', () {
        final index = seeded();
        expect(index.runCount, 3);
        expect(index.length, 10);
        expect(index.liveLength, 4);
        expect(index.lengthOf('a'), 4);
        expect(index.liveLengthOf('c'), 0);
      });

      test('liveAt answers with the run and how far into it to go', () {
        final index = seeded();
        expect(index.liveAt(0), (key: 'a', liveOffset: 0));
        expect(index.liveAt(2), (key: 'a', liveOffset: 2));
        // Past a's three live elements, so the next run opens.
        expect(index.liveAt(3), (key: 'b', liveOffset: 0));
        // c holds five elements and no live one, so nothing lands in it.
        expect(index.liveAt(4), isNull);
      });

      test('liveRankOfRunStart stops at the first element of the run', () {
        final index = seeded();
        expect(index.liveRankOfRunStart('a'), 0);
        expect(index.liveRankOfRunStart('b'), 3);
        // Counted even though none of c is live.
        expect(index.liveRankOfRunStart('c'), 4);
      });

      test('forEachLiveRun skips the runs with nothing live left', () {
        final visited = <String>[];
        seeded().forEachLiveRun((key, length, liveLength) {
          visited.add('$key:$length/$liveLength');
        });
        expect(visited, equals(['a:4/3', 'b:1/1']));
      });

      test('forEachRun reports every run, dead ones included', () {
        final visited = <String>[];
        seeded().forEachRun((key, length, liveLength) {
          visited.add('$key:$length/$liveLength');
        });
        expect(visited, equals(['a:4/3', 'b:1/1', 'c:5/0']));
      });
    });

    group('forEachRunFromLive', () {
      // 0..5, single elements, with 1 and 3 dead: live sequence 0, 2, 4, 5.
      SqrtDecomposition<int> seeded() {
        return _singles(6)
          ..setLengths(1, length: 1, liveLength: 0)
          ..setLengths(3, length: 1, liveLength: 0);
      }

      test('starts at the run holding the position and walks forward', () {
        expect(
          _runsFrom(seeded(), 1, 2),
          equals([(key: 2, liveOffset: 0), (key: 3, liveOffset: 0)]),
        );
      });

      test('carries the live offset on the first run only', () {
        final index = SqrtDecomposition<String>()
          ..insertAtFront('a', length: 4, liveLength: 3)
          ..insertAfter('a', 'b', length: 2, liveLength: 2);

        expect(
          _runsFrom(index, 2, 2),
          equals([(key: 'a', liveOffset: 2), (key: 'b', liveOffset: 0)]),
        );
      });

      test('stops at the end instead of padding', () {
        expect(
          _runsFrom(seeded(), 3, 10),
          equals([(key: 5, liveOffset: 0)]),
        );
      });

      test('yields nothing outside the live sequence', () {
        final index = seeded();
        expect(_runsFrom(index, 4, 3), isEmpty);
        expect(_runsFrom(index, -1, 3), isEmpty);
        expect(_runsFrom(index, 0, 0), isEmpty);
        expect(_runsFrom(SqrtDecomposition<int>(), 0, 3), isEmpty);
      });
    });

    test('bulkBuild reproduces the sequence', () {
      final keys = List.generate(500, (i) => i);
      final lengths = List.generate(500, (i) => 1 + (i % 3));
      final liveLengths = List.generate(500, (i) => i.isEven ? 1 + (i % 3) : 0);
      final index = SqrtDecomposition<int>()
        ..bulkBuild(keys, lengths, liveLengths);

      expect(index.runCount, 500);
      expect(index.length, lengths.fold<int>(0, (a, b) => a + b));
      expect(index.liveLength, liveLengths.fold<int>(0, (a, b) => a + b));
      expect(index.last(), 499);
      expect(index.liveAt(0), (key: 0, liveOffset: 0));
      expect(index.predecessorOf(20), 19);

      // Against the model, position by position.
      final model = _Model<int>();
      for (var i = 0; i < keys.length; i++) {
        model
          ..keys.add(keys[i])
          ..lengths.add(lengths[i])
          ..liveLengths.add(liveLengths[i]);
      }
      for (var p = 0; p < model.liveTotal; p++) {
        expect(index.liveAt(p), model.liveAt(p), reason: 'liveAt($p)');
      }
    });

    test('block splitting preserves order across many inserts', () {
      final index = _singles(2000);

      expect(index.runCount, 2000);
      expect(index.length, 2000);
      for (var i = 0; i < 2000; i++) {
        expect(index.liveAt(i), (key: i, liveOffset: 0));
      }
      expect(index.liveAt(2000), isNull);
      expect(index.last(), 1999);
      expect(index.liveRankOfRunStart(1234), 1234);
      expect(index.predecessorOf(1234), 1233);
    });

    test('a split keeps the block sums right', () {
      // Every run stands for more than one element, so a split that forgot to
      // re-sum one half would show up as a wrong total or a wrong liveAt.
      final index = SqrtDecomposition<int>()
        ..insertAtFront(0, length: 3, liveLength: 2);
      for (var key = 1; key < 400; key++) {
        index.insertAfter(key - 1, key, length: 3, liveLength: 2);
      }

      expect(index.length, 1200);
      expect(index.liveLength, 800);
      expect(index.liveAt(799), (key: 399, liveOffset: 1));
      expect(index.liveAt(800), isNull);
      expect(index.liveRankOfRunStart(399), 798);
    });

    test('append-only and prepend-only sequences agree with the model', () {
      // The two shapes the block-edge fast paths in `offsetOf` target: the
      // predecessor is always the last key of its block when appending, and
      // always the first when prepending.
      for (final appendOnly in [true, false]) {
        final index = SqrtDecomposition<int>();
        final model = _Model<int>();

        for (var key = 0; key < 900; key++) {
          final length = 1 + (key % 4);
          final liveLength = key.isEven ? length : 0;
          if (appendOnly && key > 0) {
            index.insertAfter(
              key - 1,
              key,
              length: length,
              liveLength: liveLength,
            );
            model.insertAfter(
              key - 1,
              key,
              length: length,
              liveLength: liveLength,
            );
          } else {
            index.insertAtFront(key, length: length, liveLength: liveLength);
            model.insertAtFront(key, length: length, liveLength: liveLength);
          }
        }

        expect(index.length, model.total);
        expect(index.liveLength, model.liveTotal);
        for (var position = 0; position < model.liveTotal; position++) {
          expect(index.liveAt(position), model.liveAt(position));
        }
        for (final key in model.keys) {
          expect(index.liveRankOfRunStart(key), model.liveRankOfRunStart(key));
        }
      }
    });

    test('randomized differential against the model', () {
      final rng = Random(20240607);
      final index = SqrtDecomposition<int>();
      final model = _Model<int>();
      var nextKey = 0;

      for (var step = 0; step < 4000; step++) {
        final op = rng.nextInt(10);
        if (op < 5 || model.keys.isEmpty) {
          final key = nextKey++;
          final length = 1 + rng.nextInt(5);
          final liveLength = rng.nextInt(length + 1);
          if (model.keys.isEmpty || rng.nextInt(5) == 0) {
            index.insertAtFront(key, length: length, liveLength: liveLength);
            model.insertAtFront(key, length: length, liveLength: liveLength);
          } else {
            final after = model.keys[rng.nextInt(model.keys.length)];
            index.insertAfter(
              after,
              key,
              length: length,
              liveLength: liveLength,
            );
            model.insertAfter(
              after,
              key,
              length: length,
              liveLength: liveLength,
            );
          }
        } else if (op < 8) {
          // Re-weigh a run: growing it, shrinking it (a split), or taking some
          // of its elements out of the sequence.
          final key = model.keys[rng.nextInt(model.keys.length)];
          final length = 1 + rng.nextInt(6);
          final liveLength = rng.nextInt(length + 1);
          index.setLengths(key, length: length, liveLength: liveLength);
          model.setLengths(key, length: length, liveLength: liveLength);
        }

        // Spot-check invariants every few steps (and always near the end).
        if (step % 7 == 0 || step > 3950) {
          expect(index.runCount, model.keys.length);
          expect(index.first(), model.first());
          expect(index.last(), model.last());
          // The two running sums are maintained by hand on every path that can
          // change them, so they are worth checking against a count.
          expect(index.length, model.total, reason: 'length at $step');
          final liveTotal = model.liveTotal;
          expect(index.liveLength, liveTotal, reason: 'liveLength at $step');
          expect(index.liveAt(liveTotal), isNull);
          expect(index.liveAt(-1), isNull);
          for (var p = 0; p < liveTotal; p++) {
            expect(
              index.liveAt(p),
              model.liveAt(p),
              reason: 'liveAt($p) mismatch at step $step',
            );
            expect(
              _runsFrom(index, p, 3),
              model.runsFromLive(p, 3),
              reason: 'forEachRunFromLive($p, 3) mismatch at step $step',
            );
          }
          for (final key in model.keys) {
            expect(
              index.liveRankOfRunStart(key),
              model.liveRankOfRunStart(key),
              reason: 'liveRankOfRunStart($key) mismatch at step $step',
            );
            expect(
              index.lengthOf(key),
              model.lengthOf(key),
              reason: 'lengthOf($key) mismatch at step $step',
            );
            expect(
              index.liveLengthOf(key),
              model.liveLengthOf(key),
              reason: 'liveLengthOf($key) mismatch at step $step',
            );
            expect(
              index.predecessorOf(key),
              model.predecessorOf(key),
              reason: 'predecessorOf($key) mismatch at step $step',
            );
            expect(
              index.successorOf(key),
              model.successorOf(key),
              reason: 'successorOf($key) mismatch at step $step',
            );
          }
        }
      }
    });
  });
}
