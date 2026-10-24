// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/src/utils/compact_set.dart';
import 'package:test/test.dart';

void main() {
  group('CompactSet', () {
    test('starts empty', () {
      final set = CompactSet<int>();
      expect(set.isEmpty, isTrue);
      expect(set.isNotEmpty, isFalse);
      expect(set.length, 0);
      expect(set.toList(), isEmpty);
      expect(set.contains(1), isFalse);
      expect(set.lookup(1), isNull);
      expect(set.remove(1), isFalse);
    });

    test('holds one element, once', () {
      final set = CompactSet<int>();
      expect(set.add(1), isTrue);
      expect(set.add(1), isFalse);
      expect(set.length, 1);
      expect(set.isNotEmpty, isTrue);
      expect(set.contains(1), isTrue);
      expect(set.contains(2), isFalse);
      expect(set.lookup(1), 1);
      expect(set.lookup(2), isNull);
      expect(set.toList(), [1]);
      expect(set.remove(2), isFalse);
    });

    test('grows past one element and shrinks back', () {
      final set = CompactSet<int>()..addAll([1, 2, 3]);
      expect(set.length, 3);
      expect(set.add(2), isFalse);
      expect(set.contains(3), isTrue);
      expect(set.lookup(2), 2);
      expect(set.toSet(), {1, 2, 3});

      expect(set.remove(9), isFalse);
      expect(set.remove(1), isTrue);
      expect(set.remove(2), isTrue);
      expect(set.length, 1);
      expect(set.toList(), [3]);

      expect(set.remove(3), isTrue);
      expect(set.isEmpty, isTrue);
      expect(set.add(4), isTrue);
      expect(set.toList(), [4]);
    });

    test('removeWhere and clear work in every size', () {
      final set = CompactSet<int>()
        ..addAll([1, 2, 3, 4])
        ..removeWhere((e) => e.isEven);
      expect(set.toSet(), {1, 3});

      set.removeWhere((e) => e == 1);
      expect(set.toList(), [3]);

      set.clear();
      expect(set.isEmpty, isTrue);

      final many = CompactSet<int>()
        ..addAll([1, 2])
        ..clear();
      expect(many.isEmpty, isTrue);
    });
  });
}
