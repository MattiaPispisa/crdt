// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

RichTextDelta _d(List<RichTextOp> ops) => RichTextDelta(ops);

const _image = <String, Object?>{'image': 'a.png'};
const _video = <String, Object?>{'video': 'b.mp4'};

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

    test('formats, updates and inserts embeds', () {
      final base = [RichTextSpan('a'), RichTextSpan.embed(_image)];
      final delta = _d([
        RichTextRetain(1),
        RichTextUpdateEmbed(_video, {'width': 2}),
        RichTextInsertEmbed(_image),
      ]);
      expect(delta.apply(base), [
        RichTextSpan('a'),
        RichTextSpan.embed(_video, {'width': 2}),
        RichTextSpan.embed(_image),
      ]);
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

    group('an embed', () {
      test('insert then retain merges the attributes', () {
        expect(
          _d([
            RichTextInsertEmbed(_image, {'bold': true}),
          ]).compose(
            _d([
              RichTextRetain(1, {'bold': null, 'width': 1}),
            ]),
          ),
          _d([
            RichTextInsertEmbed(_image, {'width': 1}),
          ]),
        );
      });

      test('insert then update keeps the insert with the new data', () {
        expect(
          _d([
            RichTextInsertEmbed(_image, {'bold': true}),
          ]).compose(_d([RichTextUpdateEmbed(_video)])),
          _d([
            RichTextInsertEmbed(_video, {'bold': true}),
          ]),
        );
      });

      test('update then update keeps the last', () {
        expect(
          _d([RichTextUpdateEmbed(_image)])
              .compose(_d([RichTextUpdateEmbed(_video)])),
          _d([RichTextUpdateEmbed(_video)]),
        );
      });

      test('insert then delete cancels out', () {
        expect(
          _d([RichTextInsertEmbed(_image)])
              .compose(_d([const RichTextDelete(1)])),
          const RichTextDelta.empty(),
        );
      });

      test('a format then an update keeps both', () {
        expect(
          _d([
            RichTextRetain(1, {'bold': null}),
          ]).compose(_d([RichTextUpdateEmbed(_video)])),
          _d([
            RichTextUpdateEmbed(_video, {'bold': null}),
          ]),
        );
      });
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
          switch (random.nextInt(5)) {
            case 0 when count > 0:
              ops.add(RichTextRetain(count, attributes(nulls: true)));
              left -= count;
            case 1 when count > 0:
              ops.add(RichTextDelete(count));
              left -= count;
            case 2:
              ops.add(
                RichTextInsertEmbed(
                  {'n': random.nextInt(3)},
                  attributes(nulls: false),
                ),
              );
            case 3 when count > 0:
              ops.add(
                RichTextUpdateEmbed(
                  {'n': random.nextInt(3)},
                  attributes(nulls: true),
                ),
              );
              left -= 1;
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
          RichTextSpan.embed(_image),
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

    test('an embed insert is one rune, an update moves nothing', () {
      final delta = _d([
        RichTextRetain(1),
        RichTextInsertEmbed(_image),
        RichTextUpdateEmbed(_video),
      ]);
      expect(delta.mapOffset(1), 1);
      expect(delta.mapOffset(2), 3);
      expect(delta.mapOffset(3), 4);
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
      final span = RichTextSpan('x', {'a': 1, 'b': 2});
      expect(span, RichTextSpan('x', {'b': 2, 'a': 1}));
      expect(span.hashCode, RichTextSpan('x', {'b': 2, 'a': 1}).hashCode);
      expect(RichTextSpan.embed(_image), isNot(RichTextSpan.embed(_video)));
      expect(RichTextSpan.embed(_image), isNot(RichTextSpan('\uFFFC')));
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
      expect(
        _d([
          const RichTextDelete(1),
          RichTextInsertEmbed(_image),
          RichTextInsertEmbed(_image),
          RichTextUpdateEmbed(_video),
        ]).ops,
        [
          RichTextInsertEmbed(_image),
          RichTextInsertEmbed(_image),
          const RichTextDelete(1),
          RichTextUpdateEmbed(_video),
        ],
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
