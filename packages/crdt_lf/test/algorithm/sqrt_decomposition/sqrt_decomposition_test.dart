import 'dart:math';

import 'package:crdt_lf/src/algorithm/sqrt_decomposition/sqrt_decomposition.dart';
import 'package:test/test.dart';

/// A trivial reference model: a plain ordered list of `(key, live)` pairs.
///
/// Every public query of [SqrtDecomposition] is mirrored here with an obvious
/// `O(n)` implementation; the randomized test asserts the two agree.
class _Model<T> {
  final List<T> keys = [];
  final List<bool> live = [];

  void insertAfter(T predecessor, T key, {required bool isLive}) {
    final at = keys.indexOf(predecessor);
    keys.insert(at + 1, key);
    live.insert(at + 1, isLive);
  }

  void insertAtFront(T key, {required bool isLive}) {
    keys.insert(0, key);
    live.insert(0, isLive);
  }

  void setLive(T key, {required bool isLive}) {
    live[keys.indexOf(key)] = isLive;
  }

  T? liveAt(int position) {
    if (position < 0) {
      return null;
    }
    var remaining = position;
    for (var i = 0; i < keys.length; i++) {
      if (live[i]) {
        if (remaining == 0) {
          return keys[i];
        }
        remaining--;
      }
    }
    return null;
  }

  int liveRankOf(T key) {
    final at = keys.indexOf(key);
    if (at == -1) {
      return -1;
    }
    var rank = 0;
    for (var i = 0; i < at; i++) {
      if (live[i]) {
        rank++;
      }
    }
    return rank;
  }

  T? predecessorOf(T key) {
    final at = keys.indexOf(key);
    if (at <= 0) {
      return null;
    }
    return keys[at - 1];
  }

  T? last() => keys.isEmpty ? null : keys.last;

  int get liveTotal => live.where((l) => l).length;
}

void main() {
  group('SqrtDecomposition', () {
    test('empty index', () {
      final index = SqrtDecomposition<int>();
      expect(index.length, 0);
      expect(index.liveAt(0), isNull);
      expect(index.liveAt(-1), isNull);
      expect(index.last(), isNull);
      expect(index.predecessorOf(1), isNull);
      expect(index.liveRankOf(1), -1);
      expect(index.contains(1), isFalse);
    });

    test('insertAtFront builds a reversed sequence', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(3, live: true)
        ..insertAtFront(2, live: true)
        ..insertAtFront(1, live: true);

      expect(index.length, 3);
      expect(index.liveAt(0), 1);
      expect(index.liveAt(1), 2);
      expect(index.liveAt(2), 3);
      expect(index.liveAt(3), isNull);
      expect(index.last(), 3);
    });

    test('insertAfter places keys in order', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(1, live: true)
        ..insertAfter(1, 2, live: true)
        ..insertAfter(2, 3, live: true)
        ..insertAfter(1, 5, live: true); // between 1 and 2

      expect(
        [for (var i = 0; i < index.length; i++) index.liveAt(i)],
        [1, 5, 2, 3],
      );
      expect(index.predecessorOf(5), 1);
      expect(index.predecessorOf(2), 5);
      expect(index.predecessorOf(1), isNull);
      expect(index.liveRankOf(3), 3);
      expect(index.liveRankOf(1), 0);
    });

    test('setLive removes/restores a key from the live order', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(1, live: true)
        ..insertAfter(1, 2, live: true)
        ..insertAfter(2, 3, live: true)
        ..setLive(2, live: false);

      expect(index.liveAt(0), 1);
      expect(index.liveAt(1), 3); // 2 is tombstoned, skipped
      expect(index.liveAt(2), isNull);
      // tombstone keeps its slot, so neighbours still resolve
      expect(index.predecessorOf(3), 2);
      // ranks count only live keys
      expect(index.liveRankOf(3), 1);

      index.setLive(2, live: true);
      expect(index.liveAt(1), 2);
      expect(index.liveRankOf(3), 2);
    });

    test('inserting a tombstone keeps order but not the live count', () {
      final index = SqrtDecomposition<int>()
        ..insertAtFront(1, live: true)
        ..insertAfter(1, 2, live: false) // dead
        ..insertAfter(2, 3, live: true);

      expect(index.length, 3);
      expect(index.liveAt(0), 1);
      expect(index.liveAt(1), 3);
      expect(index.predecessorOf(3), 2);
    });

    test('bulkBuild reproduces the sequence', () {
      final keys = List.generate(500, (i) => i);
      final live = List.generate(500, (i) => i.isEven);
      final index = SqrtDecomposition<int>()..bulkBuild(keys, live);

      expect(index.length, 500);
      expect(index.last(), 499);
      // i-th live key is the i-th even number
      expect(index.liveAt(0), 0);
      expect(index.liveAt(10), 20);
      expect(index.liveRankOf(20), 10);
      expect(index.predecessorOf(20), 19);
    });

    test('block splitting preserves order across many inserts', () {
      final index = SqrtDecomposition<int>()..insertAtFront(0, live: true);
      // Append 0,1,2,... each after the previous → forces repeated splits.
      for (var i = 1; i < 2000; i++) {
        index.insertAfter(i - 1, i, live: true);
      }

      expect(index.length, 2000);
      for (var i = 0; i < 2000; i++) {
        expect(index.liveAt(i), i);
      }
      expect(index.liveAt(2000), isNull);
      expect(index.last(), 1999);
      expect(index.liveRankOf(1234), 1234);
      expect(index.predecessorOf(1234), 1233);
    });

    test('randomized differential test against a reference model', () {
      final rng = Random(20240607);
      final index = SqrtDecomposition<int>();
      final model = _Model<int>();
      var nextKey = 0;

      for (var step = 0; step < 4000; step++) {
        final present = model.keys;
        final choice = rng.nextInt(10);

        if (present.isEmpty || choice < 5) {
          // insert
          final key = nextKey++;
          final live = rng.nextBool();
          if (present.isEmpty || rng.nextInt(5) == 0) {
            index.insertAtFront(key, live: live);
            model.insertAtFront(key, isLive: live);
          } else {
            final pred = present[rng.nextInt(present.length)];
            index.insertAfter(pred, key, live: live);
            model.insertAfter(pred, key, isLive: live);
          }
        } else if (choice < 8) {
          // toggle liveness
          final key = present[rng.nextInt(present.length)];
          final live = rng.nextBool();
          index.setLive(key, live: live);
          model.setLive(key, isLive: live);
        }

        // Spot-check invariants every few steps (and always near the end).
        if (step % 7 == 0 || step > 3950) {
          expect(index.length, model.keys.length);
          expect(index.last(), model.last());
          final liveTotal = model.liveTotal;
          expect(index.liveAt(liveTotal), isNull);
          expect(index.liveAt(-1), isNull);
          for (var p = 0; p < liveTotal; p++) {
            expect(
              index.liveAt(p),
              model.liveAt(p),
              reason: 'liveAt($p) mismatch at step $step',
            );
          }
          for (final key in model.keys) {
            expect(
              index.liveRankOf(key),
              model.liveRankOf(key),
              reason: 'liveRankOf($key) mismatch at step $step',
            );
            expect(
              index.predecessorOf(key),
              model.predecessorOf(key),
              reason: 'predecessorOf($key) mismatch at step $step',
            );
          }
        }
      }
    });
  });
}
