import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// A delta that is valid for a base of [length] elements.
SequenceDelta<String> _randomDelta(Random random, int length) {
  final ops = <SeqOp<String>>[];
  var index = 0;
  var counter = 0;

  while (index < length) {
    final left = length - index;
    switch (random.nextInt(3)) {
      case 0:
        final count = 1 + random.nextInt(left);
        ops.add(SeqRetain<String>(count));
        index += count;
      case 1:
        final count = 1 + random.nextInt(3);
        ops.add(
          SeqInsert<String>(
            List.generate(count, (_) => 'n${counter++}'),
          ),
        );
      case 2:
        final count = 1 + random.nextInt(left);
        ops.add(SeqDelete<String>(count));
        index += count;
    }
  }

  if (random.nextBool()) {
    ops.add(SeqInsert<String>(['tail${counter++}']));
  }

  return SequenceDelta<String>(ops);
}

void main() {
  group('SequenceDelta.apply', () {
    test('retain, insert and delete run left to right', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(1),
        const SeqInsert<String>(['x', 'y']),
        const SeqDelete<String>(1),
      ]);

      expect(delta.apply(['a', 'b', 'c']), ['a', 'x', 'y', 'c']);
    });

    test('the untouched tail survives', () {
      final delta = SequenceDelta<String>([
        const SeqInsert<String>(['x']),
      ]);

      expect(delta.apply(['a', 'b']), ['x', 'a', 'b']);
    });

    test('the base is left alone', () {
      final base = ['a', 'b'];
      SequenceDelta<String>([const SeqDelete<String>(1)]).apply(base);

      expect(base, ['a', 'b']);
    });

    test('a move keeps the element', () {
      final delta = SequenceDelta<String>([
        const SeqMove<String>(from: 0, to: 2),
      ]);

      expect(delta.apply(['a', 'b', 'c']), ['b', 'c', 'a']);
    });
  });

  group('SequenceDelta.applyToText', () {
    test('splices by rune', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(5),
        seqInsertText(' brave'),
      ]);

      expect(delta.applyToText('hello world'), 'hello brave world');
    });

    test('a non-BMP character counts as one element', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(1),
        const SeqDelete<String>(1),
      ]);

      // Two emoji: retaining one and deleting one leaves the first whole.
      expect(delta.applyToText('🌐🌏'), '🌐');
    });

    test('inserted non-BMP text round-trips', () {
      final delta = SequenceDelta<String>([seqInsertText('🌐a')]);

      expect(delta.applyToText(''), '🌐a');
      expect((delta.ops.first as SeqInsert<String>).values.length, 2);
    });
  });

  group('SequenceDelta.compose', () {
    test('retain then retain keeps the base', () {
      final a = SequenceDelta<String>([const SeqRetain<String>(2)]);
      final b = SequenceDelta<String>([const SeqRetain<String>(2)]);

      expect(a.compose(b).isEmpty, isTrue);
    });

    test('two contiguous inserts fuse into one', () {
      final a = SequenceDelta<String>([seqInsertText('ab')]);
      final b = SequenceDelta<String>([
        const SeqRetain<String>(2),
        seqInsertText('c'),
      ]);

      expect(a.compose(b), SequenceDelta<String>([seqInsertText('abc')]));
    });

    test('an insert removed by the next delta cancels out', () {
      final a = SequenceDelta<String>([seqInsertText('xy')]);
      final b = SequenceDelta<String>([const SeqDelete<String>(2)]);

      expect(a.compose(b).isEmpty, isTrue);
    });

    test('an insert partially removed keeps the remainder', () {
      final a = SequenceDelta<String>([seqInsertText('xyz')]);
      final b = SequenceDelta<String>([
        const SeqRetain<String>(1),
        const SeqDelete<String>(1),
      ]);

      expect(a.compose(b), SequenceDelta<String>([seqInsertText('xz')]));
    });

    test('a retain then a delete removes the base element', () {
      final a = SequenceDelta<String>([
        const SeqRetain<String>(1),
        seqInsertText('x'),
      ]);
      final b = SequenceDelta<String>([const SeqDelete<String>(1)]);

      expect(
        a.compose(b),
        SequenceDelta<String>([
          const SeqDelete<String>(1),
          seqInsertText('x'),
        ]),
      );
    });

    test('a delete of the first delta passes through', () {
      final a = SequenceDelta<String>([const SeqDelete<String>(1)]);
      final b = SequenceDelta<String>([seqInsertText('x')]);

      expect(
        a.compose(b),
        SequenceDelta<String>([
          seqInsertText('x'),
          const SeqDelete<String>(1),
        ]),
      );
    });

    test('a trailing retain is dropped', () {
      final a = SequenceDelta<String>([seqInsertText('x')]);
      final b = SequenceDelta<String>([const SeqRetain<String>(5)]);

      expect(a.compose(b).ops, [seqInsertText('x')]);
    });

    test('a move refuses to compose', () {
      final move = SequenceDelta<String>([
        const SeqMove<String>(from: 0, to: 1),
      ]);

      expect(
        () => move.compose(const SequenceDelta<String>.empty()),
        throwsUnsupportedError,
      );
    });

    test('composing equals applying in order, over random deltas', () {
      final random = Random(11);

      for (var round = 0; round < 400; round++) {
        final length = 1 + random.nextInt(8);
        final base = List.generate(length, (i) => 'b$i');

        final a = _randomDelta(random, length);
        final middle = a.apply(base);
        final b = _randomDelta(random, middle.length);

        expect(
          a.compose(b).apply(base),
          b.apply(middle),
          reason: 'round $round: $a then $b over $base',
        );
      }
    });
  });

  group('SequenceDelta.mapOffset', () {
    test('an offset before the splice does not move', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(4),
        seqInsertText('brave '),
      ]);

      expect(delta.mapOffset(0), 0);
      expect(delta.mapOffset(3), 3);
    });

    test('an offset at the insertion point stays in front of it', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(4),
        seqInsertText('xx'),
      ]);

      expect(delta.mapOffset(4), 4);
    });

    test('an offset after the insertion point shifts by its length', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(4),
        seqInsertText('xx'),
      ]);

      expect(delta.mapOffset(5), 7);
    });

    test('an offset inside a removed run lands on the splice', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(2),
        const SeqDelete<String>(3),
      ]);

      expect(delta.mapOffset(3), 2);
      expect(delta.mapOffset(5), 2);
      expect(delta.mapOffset(6), 3);
    });

    test('a replacement puts the offset past the new text', () {
      final delta = SequenceDelta<String>([
        const SeqRetain<String>(2),
        const SeqDelete<String>(3),
        seqInsertText('xy'),
      ]);

      expect(delta.mapOffset(4), 4);
      expect(delta.mapOffset(2), 2);
    });

    test('a move refuses to map an offset', () {
      final delta = SequenceDelta<String>([
        const SeqMove<String>(from: 0, to: 1),
      ]);

      expect(() => delta.mapOffset(0), throwsUnsupportedError);
    });
  });

  group('SequenceDelta value semantics', () {
    test('the empty delta moves nothing', () {
      const delta = SequenceDelta<String>.empty();

      expect(delta.isEmpty, isTrue);
      expect(delta.isNotEmpty, isFalse);
    });

    test('a delta that holds a step is not empty', () {
      final delta = SequenceDelta<String>([const SeqRetain<String>(1)]);

      expect(delta.isEmpty, isFalse);
      expect(delta.isNotEmpty, isTrue);
    });

    test('the same steps make equal deltas', () {
      final a = SequenceDelta<String>([
        const SeqRetain<String>(2),
        seqInsertText('hi'),
      ]);
      final b = SequenceDelta<String>([
        const SeqRetain<String>(2),
        seqInsertText('hi'),
      ]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('steps of one length but different kinds are told apart', () {
      final retained = SequenceDelta<String>([const SeqRetain<String>(1)]);
      final deleted = SequenceDelta<String>([const SeqDelete<String>(1)]);

      expect(retained, isNot(deleted));
      expect(const SeqRetain<String>(1), isNot(const SeqDelete<String>(1)));
    });

    test('a step is equal to the same step', () {
      expect(
        const SeqRetain<String>(2).hashCode,
        const SeqRetain<String>(2).hashCode,
      );
      expect(
        const SeqDelete<String>(2).hashCode,
        const SeqDelete<String>(2).hashCode,
      );
      expect(seqInsertText('hi').hashCode, seqInsertText('hi').hashCode);
      expect(
        const SeqMove<String>(from: 0, to: 2).hashCode,
        const SeqMove<String>(from: 0, to: 2).hashCode,
      );
    });

    test('an insert reads back as the text it carries', () {
      expect(seqInsertText('h\u{1F600}i').text, 'h\u{1F600}i');
    });

    test('the descriptions name the steps', () {
      expect(
        const SeqMove<String>(from: 0, to: 2).toString(),
        'SeqMove(0 -> 2)',
      );
      expect(
        SequenceDelta<String>([const SeqRetain<String>(1)]).toString(),
        contains('SeqRetain'),
      );
    });
  });
}
