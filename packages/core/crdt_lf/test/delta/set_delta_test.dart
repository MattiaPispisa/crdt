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

  group('SetDelta value semantics', () {
    test('the empty delta moves nothing', () {
      const delta = SetDelta<String>.empty();

      expect(delta.isEmpty, isTrue);
      expect(delta.isNotEmpty, isFalse);
      expect(delta.apply({'a'}), {'a'});
    });

    test('a delta that moves something is not empty', () {
      const delta = SetDelta<String>(added: {'a'}, removed: {});

      expect(delta.isEmpty, isFalse);
      expect(delta.isNotEmpty, isTrue);
    });

    test('equality ignores the order the values were listed in', () {
      const a = SetDelta<String>(added: {'a', 'b'}, removed: {'c'});
      const b = SetDelta<String>(added: {'b', 'a'}, removed: {'c'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('added and removed are told apart', () {
      const a = SetDelta<String>(added: {'a'}, removed: {});
      const b = SetDelta<String>(added: {}, removed: {'a'});

      expect(a, isNot(b));
    });

    test('the description names both sides', () {
      const delta = SetDelta<String>(added: {'a'}, removed: {'b'});

      expect(delta.toString(), contains('added: {a}'));
      expect(delta.toString(), contains('removed: {b}'));
    });
  });
}
