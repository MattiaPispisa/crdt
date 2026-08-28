import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

MapDelta<String, String> _randomDelta(Random random, Map<String, String> base) {
  final entries = <String, MapEntryChange<String>>{};
  final keys = ['a', 'b', 'c'];

  for (final key in keys) {
    switch (random.nextInt(3)) {
      case 0:
        entries[key] = MapEntrySet<String>(
          value: 'v${random.nextInt(5)}',
          previous: base[key],
        );
      case 1:
        final previous = base[key];
        if (previous != null) {
          entries[key] = MapEntryRemoved<String>(previous: previous);
        }
      case 2:
        break;
    }
  }

  return MapDelta<String, String>(entries);
}

void main() {
  group('MapDelta.apply', () {
    test('a set writes the key and a removal drops it', () {
      const delta = MapDelta<String, String>({
        'a': MapEntrySet<String>(value: '1', previous: null),
        'b': MapEntryRemoved<String>(previous: 'old'),
      });

      expect(delta.apply({'b': 'old', 'c': 'keep'}), {'a': '1', 'c': 'keep'});
    });

    test('the base is left alone', () {
      final base = {'a': '1'};
      const MapDelta<String, String>({
        'a': MapEntryRemoved<String>(previous: '1'),
      }).apply(base);

      expect(base, {'a': '1'});
    });
  });

  group('MapDelta.compose', () {
    test('a key touched twice keeps the first starting point', () {
      const a = MapDelta<String, String>({
        'k': MapEntrySet<String>(value: '1', previous: 'origin'),
      });
      const b = MapDelta<String, String>({
        'k': MapEntrySet<String>(value: '2', previous: '1'),
      });

      expect(
        a.compose(b),
        const MapDelta<String, String>({
          'k': MapEntrySet<String>(value: '2', previous: 'origin'),
        }),
      );
    });

    test('a key put in and taken out again disappears from the delta', () {
      const a = MapDelta<String, String>({
        'k': MapEntrySet<String>(value: '1', previous: null),
      });
      const b = MapDelta<String, String>({
        'k': MapEntryRemoved<String>(previous: '1'),
      });

      expect(a.compose(b).isEmpty, isTrue);
    });

    test('a key that existed before is still reported as removed', () {
      const a = MapDelta<String, String>({
        'k': MapEntrySet<String>(value: '1', previous: 'origin'),
      });
      const b = MapDelta<String, String>({
        'k': MapEntryRemoved<String>(previous: '1'),
      });

      expect(
        a.compose(b),
        const MapDelta<String, String>({
          'k': MapEntryRemoved<String>(previous: 'origin'),
        }),
      );
    });

    test('untouched keys of either side survive', () {
      const a = MapDelta<String, String>({
        'a': MapEntrySet<String>(value: '1', previous: null),
      });
      const b = MapDelta<String, String>({
        'b': MapEntrySet<String>(value: '2', previous: null),
      });

      expect(a.compose(b).entries.keys, unorderedEquals(['a', 'b']));
    });

    test('composing equals applying in order, over random deltas', () {
      final random = Random(5);

      for (var round = 0; round < 400; round++) {
        final base = <String, String>{
          if (random.nextBool()) 'a': 'base-a',
          if (random.nextBool()) 'b': 'base-b',
        };

        final a = _randomDelta(random, base);
        final middle = a.apply(base);
        final b = _randomDelta(random, middle);

        expect(
          a.compose(b).apply(base),
          b.apply(middle),
          reason: 'round $round: $a then $b over $base',
        );
      }
    });
  });

  group('MapDelta value semantics', () {
    test('the empty delta moves nothing', () {
      const delta = MapDelta<String, int>.empty();

      expect(delta.isEmpty, isTrue);
      expect(delta.isNotEmpty, isFalse);
      expect(delta.apply({'a': 1}), {'a': 1});
    });

    test('a delta that touches a key is not empty', () {
      const delta = MapDelta<String, int>({
        'a': MapEntrySet<int>(value: 1, previous: null),
      });

      expect(delta.isEmpty, isFalse);
      expect(delta.isNotEmpty, isTrue);
    });

    test('equality ignores the order the keys were listed in', () {
      const a = MapDelta<String, int>({
        'a': MapEntrySet<int>(value: 1, previous: null),
        'b': MapEntryRemoved<int>(previous: 2),
      });
      const b = MapDelta<String, int>({
        'b': MapEntryRemoved<int>(previous: 2),
        'a': MapEntrySet<int>(value: 1, previous: null),
      });

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a write and a removal of the same key are told apart', () {
      const written = MapDelta<String, int>({
        'a': MapEntrySet<int>(value: 1, previous: null),
      });
      const removed = MapDelta<String, int>({
        'a': MapEntryRemoved<int>(previous: 1),
      });

      expect(written, isNot(removed));
    });

    test('an entry change carries the value it replaced', () {
      const first = MapEntrySet<int>(value: 1, previous: 0);
      const same = MapEntrySet<int>(value: 1, previous: 0);
      const other = MapEntrySet<int>(value: 1, previous: null);

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(other));
    });

    test('a removal is equal to a removal of the same value', () {
      const first = MapEntryRemoved<int>(previous: 1);

      expect(first, const MapEntryRemoved<int>(previous: 1));
      expect(first.hashCode, const MapEntryRemoved<int>(previous: 1).hashCode);
      expect(first, isNot(const MapEntryRemoved<int>(previous: 2)));
    });

    test('the descriptions name what moved', () {
      expect(
        const MapEntrySet<int>(value: 1, previous: 0).toString(),
        'MapEntrySet(0 -> 1)',
      );
      expect(
        const MapEntryRemoved<int>(previous: 1).toString(),
        'MapEntryRemoved(1)',
      );
    });
  });
}
