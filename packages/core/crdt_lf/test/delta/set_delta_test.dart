import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

SetDelta<String> _randomDelta(Random random, Set<String> base) {
  final added = <String>{};
  final removed = <String>{};

  for (final value in ['a', 'b', 'c']) {
    if (base.contains(value)) {
      if (random.nextBool()) {
        removed.add(value);
      }
    } else if (random.nextBool()) {
      added.add(value);
    }
  }

  return SetDelta<String>(added: added, removed: removed);
}

void main() {
  group('SetDelta.apply', () {
    test('adds then removes', () {
      const delta = SetDelta<String>(added: {'a'}, removed: {'b'});

      expect(delta.apply({'b', 'c'}), {'a', 'c'});
    });

    test('the base is left alone', () {
      final base = {'a'};
      const SetDelta<String>(added: {}, removed: {'a'}).apply(base);

      expect(base, {'a'});
    });
  });

  group('SetDelta.compose', () {
    test('a value put in and taken out cancels', () {
      const a = SetDelta<String>(added: {'x'}, removed: {});
      const b = SetDelta<String>(added: {}, removed: {'x'});

      expect(a.compose(b).isEmpty, isTrue);
    });

    test('a value taken out and put back cancels', () {
      const a = SetDelta<String>(added: {}, removed: {'x'});
      const b = SetDelta<String>(added: {'x'}, removed: {});

      expect(a.compose(b).isEmpty, isTrue);
    });

    test('composing equals applying in order, over random deltas', () {
      final random = Random(3);

      for (var round = 0; round < 400; round++) {
        final base = <String>{
          if (random.nextBool()) 'a',
          if (random.nextBool()) 'b',
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
}
