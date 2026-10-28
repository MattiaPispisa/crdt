// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

RichTextDelta _d(List<RichTextOp> ops) => RichTextDelta(ops);

void main() {
  group('RichTextDelta.apply', () {
    test('inserts, formats and deletes spans by rune', () {
      final base = [
        RichTextSpan('a\u{1F600}b', {'bold': true}),
        RichTextSpan('cd'),
      ];
      final delta = _d([
        RichTextRetain(1),
        RichTextRetain(1, {'bold': null, 'size': 2}),
        const RichTextDelete(1),
        RichTextInsert('x', {'bold': true}),
        RichTextRetain(1, {'bold': true}),
      ]);

      expect(delta.apply(base), [
        RichTextSpan('a', {'bold': true}),
        RichTextSpan('\u{1F600}', {'size': 2}),
        RichTextSpan('xc', {'bold': true}),
        RichTextSpan('d'),
      ]);
      expect(base.first.text, 'a\u{1F600}b');
    });
  });

  group('RichTextDelta.compose', () {
    test('a format over an insert lands on the insert, nulls dropped', () {
      final insert = _d([
        RichTextInsert('ab', {'bold': true}),
      ]);
      final format = _d([
        RichTextRetain(1, {'bold': null, 'size': 1}),
      ]);
      expect(
        insert.compose(format),
        _d([
          RichTextInsert('a', {'size': 1}),
          RichTextInsert('b', {'bold': true}),
        ]),
      );
    });

    test('two formats merge, and a removal stays a removal', () {
      final first = _d([
        RichTextRetain(2, {'bold': true}),
      ]);
      final second = _d([
        RichTextRetain(1, {'bold': null}),
      ]);
      expect(
        first.compose(second),
        _d([
          RichTextRetain(1, {'bold': null}),
          RichTextRetain(1, {'bold': true}),
        ]),
      );
    });

    test('an insert taken out by the next delta cancels out', () {
      final insert = _d([RichTextRetain(1), RichTextInsert('xy')]);
      final delete = _d([RichTextRetain(1), const RichTextDelete(1)]);
      expect(
        insert.compose(delete),
        _d([RichTextRetain(1), RichTextInsert('y')]),
      );
    });

    test('composing equals applying in order, over random deltas', () {
      final random = Random(7);
      const keys = ['bold', 'size'];
      Map<String, Object?> attributes({required bool nulls}) => {
            for (final key in keys)
              if (random.nextInt(3) == 0)
                key: nulls && random.nextBool() ? null : random.nextInt(2),
          };
      RichTextDelta randomDelta(int length) {
        final ops = <RichTextOp>[];
        var left = length;
        while (left > 0 || random.nextInt(3) == 0) {
          final count = left == 0 ? 0 : random.nextInt(left) + 1;
          switch (random.nextInt(3)) {
            case 0 when count > 0:
              ops.add(RichTextRetain(count, attributes(nulls: true)));
              left -= count;
            case 1 when count > 0:
              ops.add(RichTextDelete(count));
              left -= count;
            default:
              ops.add(RichTextInsert('xy\u{1F600}', attributes(nulls: false)));
          }
          if (left == 0 && random.nextBool()) {
            break;
          }
        }
        return _d(ops);
      }

      int lengthOf(List<RichTextSpan> spans) =>
          spans.fold(0, (sum, span) => sum + span.text.runes.length);

      for (var round = 0; round < 200; round++) {
        final base = [
          RichTextSpan('ab', {'bold': 1}),
          RichTextSpan('c\u{1F600}d'),
        ];
        final first = randomDelta(lengthOf(base));
        final middle = first.apply(base);
        final second = randomDelta(lengthOf(middle));
        expect(
          first.compose(second).apply(base),
          second.apply(middle),
          reason: 'round $round: $first then $second',
        );
      }
    });
  });

  group('RichTextDelta.mapOffset', () {
    test('a format moves no offset', () {
      final delta = _d([
        RichTextRetain(3, {'bold': true}),
      ]);
      expect(delta.mapOffset(2), 2);
    });

    test('an insert at the offset leaves it in front, a delete collapses', () {
      final delta = _d([
        RichTextRetain(1),
        RichTextInsert('\u{1F600}x'),
        RichTextRetain(1),
        const RichTextDelete(2),
      ]);
      expect(delta.mapOffset(1), 1);
      expect(delta.mapOffset(2), 4);
      expect(delta.mapOffset(3), 4);
      expect(delta.mapOffset(5), 5);
    });
  });

  group('RichTextDelta value semantics', () {
    test('equal ops make equal deltas, whatever the key order', () {
      final a = _d([
        RichTextRetain(1, {'a': 1, 'b': 2}),
        RichTextInsert('x'),
      ]);
      final b = _d([
        RichTextRetain(1, {'b': 2, 'a': 1}),
        RichTextInsert('x'),
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          _d([
            RichTextRetain(1, {'a': 1}),
          ]),
        ),
      );
    });

    test('neighbours fuse, an insert goes before a delete, a plain tail goes',
        () {
      expect(
        _d([
          RichTextRetain(1),
          RichTextRetain(1),
          const RichTextDelete(1),
          RichTextInsert('a'),
          RichTextInsert('b'),
          RichTextRetain(0, {'k': 1}),
          RichTextRetain(2),
        ]).ops,
        [RichTextRetain(2), RichTextInsert('ab'), const RichTextDelete(1)],
      );
      expect(_d([RichTextRetain(1)]).isEmpty, isTrue);
      expect(
        _d([
          RichTextRetain(1, {'k': 1}),
        ]).isNotEmpty,
        isTrue,
      );
    });

    test('descriptions name the ops and the attributes', () {
      expect(
        _d([
          RichTextRetain(1, {'k': null}),
          RichTextInsert('a'),
          const RichTextDelete(1),
        ]).toString(),
        'RichTextDelta([RichTextRetain(1, {k: null}), RichTextInsert("a"), '
        'RichTextDelete(1)])',
      );
      expect(
        RichTextSpan('a', {'k': 1}).toString(),
        'RichTextSpan("a", {k: 1})',
      );
    });
  });
}
