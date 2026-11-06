// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_core.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final peer = PeerId.generate();
  FugueElementID id(int n) => FugueElementID(peer, n);

  group('SelectionAnchors', () {
    late List<(FugueElementID?, FugueElementID?)> published;
    late SelectionAnchors anchors;

    setUp(() {
      published = [];
      anchors =
          SelectionAnchors((base, extent) => published.add((base, extent)))
            ..hasFocus = true;
    });

    test('publishes a change once, and nothing for the same anchors', () {
      anchors
        ..update(id(1), id(2))
        ..update(id(1), id(2));
      expect(published, [(id(1), id(2))]);
    });

    test('withdraws with nulls when the focus leaves, and not twice', () {
      anchors
        ..update(id(1), id(1))
        ..hasFocus = false
        ..update(id(3), id(3))
        ..clear();
      expect(published, [(id(1), id(1)), (null, null)]);
      expect(anchors.base, isNull);
    });

    test('anchors by rune, not by code unit', () {
      // 'a😀b': the caret after the emoji is code unit 3, rune 2.
      final runes = <int>[];
      anchors.capture(const TextSelection.collapsed(offset: 3), 'a😀b', (r) {
        runes.add(r);
        return id(r);
      });
      expect(runes, [2, 2]);
    });

    test('a missing selection has no anchor', () {
      anchors.capture(
        const TextSelection.collapsed(offset: -1),
        'ab',
        (_) => id(1),
      );
      expect(anchors.base, isNull);
      expect(anchors.extent, isNull);
    });
  });

  group('rebaseDelta', () {
    test('moves the edit through what landed meanwhile', () {
      final pushed = rebaseDelta(
        const TextDelta(index: 3, deleted: 0, inserted: 'x'),
        'abc',
        'ZZabc',
      );
      expect(pushed.single.index, 5);
    });

    test('leaves an insert at the start of the range out of the delete', () {
      expect(
        rebaseDelta(
          const TextDelta(index: 1, deleted: 2, inserted: 'he'),
          'teh',
          'tXeh',
        ),
        [const TextDelta(index: 2, deleted: 2, inserted: 'he')],
      );
    });

    test('leaves an insert at the end of the range out of the delete', () {
      expect(
        rebaseDelta(
          const TextDelta(index: 1, deleted: 2, inserted: 'he'),
          'teh',
          'tehX',
        ),
        [const TextDelta(index: 1, deleted: 2, inserted: 'he')],
      );
    });

    test('splits the delete around an insert inside the range', () {
      expect(
        rebaseDelta(
          const TextDelta(index: 1, deleted: 2, inserted: 'he'),
          'teh',
          'teXXh',
        ),
        [
          const TextDelta(index: 1, deleted: 1, inserted: 'he'),
          const TextDelta(index: 4, deleted: 1, inserted: ''),
        ],
      );
    });

    test('moves the whole range past an edit before it', () {
      expect(
        rebaseDelta(
          const TextDelta(index: 3, deleted: 1, inserted: 'x'),
          'abcd',
          'Zabcd',
        ),
        [const TextDelta(index: 4, deleted: 1, inserted: 'x')],
      );
    });

    test('deletes only what a remote deletion left of the range', () {
      expect(
        rebaseDelta(
          const TextDelta(index: 1, deleted: 3, inserted: 'x'),
          'abcdef',
          'abef',
        ),
        [const TextDelta(index: 1, deleted: 1, inserted: 'x')],
      );
      expect(
        rebaseDelta(
          const TextDelta(index: 2, deleted: 3, inserted: 'x'),
          'abcdef',
          'adef',
        ),
        [const TextDelta(index: 1, deleted: 2, inserted: 'x')],
      );
    });

    test('clamps to the merged text', () {
      final pushed = rebaseDelta(
        const TextDelta(index: 2, deleted: 1, inserted: ''),
        'abc',
        'a',
      );
      expect(pushed.single.index, 1);
      expect(pushed.single.deleted, 0);
    });
  });

  group('adoptedValue', () {
    int? none(FugueElementID _) => null;

    test('keeps a missing selection missing', () {
      final value = adoptedValue(
        old: const TextEditingValue(text: 'ab'),
        merged: 'Zab',
        baseAnchor: null,
        extentAnchor: null,
        resolve: none,
      );
      expect(value.selection.baseOffset, -1);
      expect(value.selection.extentOffset, -1);
    });

    test('the stable position wins over the reported delta', () {
      final value = adoptedValue(
        old: const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 1),
        ),
        merged: 'Zab',
        baseAnchor: id(1),
        extentAnchor: id(1),
        resolve: (_) => 3,
        mapReported: (rune) => 0,
      );
      expect(value.selection, const TextSelection.collapsed(offset: 3));
    });

    test('maps through the reported delta when there is no anchor', () {
      final value = adoptedValue(
        old: const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 1),
        ),
        merged: 'Zab',
        baseAnchor: null,
        extentAnchor: null,
        resolve: none,
        mapReported: (rune) => rune + 1,
      );
      expect(value.selection, const TextSelection.collapsed(offset: 2));
    });

    test('falls back to a diff of the texts', () {
      final value = adoptedValue(
        old: const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
        merged: 'Zab',
        baseAnchor: null,
        extentAnchor: null,
        resolve: none,
      );
      expect(value.selection, const TextSelection.collapsed(offset: 3));
    });
  });

  group('echoesSequence', () {
    SequenceDelta<String> seq(List<SeqOp<String>> ops) =>
        SequenceDelta<String>(ops);

    test('a sequence write is its own echo', () {
      final dropped = [
        seq([const SeqRetain<String>(2), const SeqDelete<String>(1)]),
        seq([
          const SeqRetain<String>(2),
          const SeqInsert<String>(['x', 'y']),
        ]),
      ];
      expect(echoesSequence(dropped, deleted: 1, inserted: 2), isTrue);
    });

    test('an extra insert, or an extra delete, is foreign', () {
      final write = seq([
        const SeqInsert<String>(['x']),
      ]);
      final extraInsert = seq([
        const SeqInsert<String>(['H']),
      ]);
      final extraDelete = seq([const SeqDelete<String>(1)]);
      expect(
        echoesSequence([write, extraInsert], deleted: 0, inserted: 1),
        isFalse,
      );
      expect(
        echoesSequence([write, extraDelete], deleted: 0, inserted: 1),
        isFalse,
      );
    });
  });
}
