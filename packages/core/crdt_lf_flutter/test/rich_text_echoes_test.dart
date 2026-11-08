// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('echoesRichText', () {
    test('a rich write owns the formats it puts on its text', () {
      final write = [
        RichTextDelta([RichTextRetain(1), RichTextInsert('ab')]),
        RichTextDelta([
          RichTextRetain(1),
          RichTextRetain(2, {'bold': true}),
        ]),
      ];
      final own = formatsWithin(1, 3, {'bold': true});
      expect(
        echoesRichText(write, deleted: 0, inserted: 2, ownsFormat: own),
        isTrue,
      );
      expect(echoesRichText(write, deleted: 0, inserted: 2), isFalse);
      expect(
        echoesRichText(
          write,
          deleted: 0,
          inserted: 2,
          ownsFormat: formatsWithin(1, 3, {'italic': true}),
        ),
        isFalse,
      );
      expect(
        echoesRichText(
          write,
          deleted: 0,
          inserted: 2,
          ownsFormat: formatsWithin(1, 3, {'bold': false}),
        ),
        isFalse,
      );
      expect(
        echoesRichText(
          [
            ...write,
            RichTextDelta([
              RichTextRetain(2, {'bold': true}),
            ]),
          ],
          deleted: 0,
          inserted: 2,
          ownsFormat: own,
        ),
        isFalse,
      );
      expect(
        echoesRichText(
          [
            ...write,
            RichTextDelta([const RichTextDelete(1)]),
          ],
          deleted: 0,
          inserted: 2,
          ownsFormat: own,
        ),
        isFalse,
      );
    });

    test('embeds are counted apart from the text', () {
      final dropped = [
        RichTextDelta([
          RichTextInsertEmbed({'image': 'a.png'}),
        ]),
        RichTextDelta([
          RichTextUpdateEmbed({'image': 'b.png'}),
        ]),
      ];
      expect(
        echoesRichText(
          dropped,
          deleted: 0,
          inserted: 0,
          embedsInserted: 1,
          embedsUpdated: 1,
        ),
        isTrue,
      );
      expect(
        echoesRichText(dropped, deleted: 0, inserted: 1, embedsUpdated: 1),
        isFalse,
      );
      expect(
        echoesRichText(dropped, deleted: 0, inserted: 0, embedsInserted: 1),
        isFalse,
      );
    });
  });

  group('RichTextEcho', () {
    const writer = RichTextWriter(expandOf: _expandOf);

    test('takes the write it recorded, and nothing else', () {
      final write = [
        RichTextDelta([
          RichTextRetain(1),
          const RichTextDelete(1),
          RichTextInsert('ab'),
          RichTextInsertEmbed(const {'type': 'image'}),
        ]),
        RichTextDelta([
          RichTextUpdateEmbed(const {'type': 'video'}, const {'bold': true}),
          RichTextRetain(2, const {'bold': true}),
        ]),
      ];
      final echo = RichTextEcho(writer);
      write.forEach(echo.add);

      expect(echo.echoes(write), isTrue);
      expect(echo.echoes(write.sublist(1)), isFalse);
      expect(
        echo.echoes([
          ...write,
          RichTextDelta([
            RichTextRetain(3, const {'italic': true}),
          ]),
        ]),
        isFalse,
      );
    });

    test('a key formatted after the insert may be cleared first, only', () {
      final echo = RichTextEcho(writer)
        ..add(
          RichTextDelta([
            RichTextInsert('ab', const {'link': 'x', 'bold': true}),
          ]),
        );

      expect(echo.ownsFormat(0, 2, const {'bold': true}), isTrue);
      expect(echo.ownsFormat(0, 2, const {'bold': null}), isFalse);
      expect(echo.ownsFormat(0, 2, const {'link': null}), isTrue);
      expect(echo.ownsFormat(0, 2, const {'link': 'x'}), isTrue);
      expect(echo.ownsFormat(0, 2, const {'link': null}), isFalse);
      expect(echo.ownsFormat(0, 3, const {'link': 'x'}), isFalse);
    });
  });
}

MarkExpand _expandOf(String key) =>
    key == 'link' ? MarkExpand.none : MarkExpand.after;
