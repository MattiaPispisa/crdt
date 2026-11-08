// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
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
}
