// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/src/utils/embed_data.dart';
import 'package:test/test.dart';

void main() {
  group('freezeEmbed', () {
    test('copies deep, keeps the key order, and cannot change', () {
      final input = <String, Object?>{
        'b': [1],
        'a': {
          'c': Uint8List.fromList([1]),
        },
      };
      final frozen = freezeEmbed(input);
      (input['b']! as List<Object?>).add(2);

      expect(frozen.keys, ['b', 'a']);
      expect(frozen['b'], [1]);
      expect(() => frozen['z'] = 1, throwsUnsupportedError);
      expect(() => (frozen['b']! as List).add(3), throwsUnsupportedError);
      final nested = frozen['a']! as Map<String, Object?>;
      expect(() => nested['z'] = 1, throwsUnsupportedError);
      expect(() => (nested['c']! as Uint8List)[0] = 2, throwsUnsupportedError);
      expect(freezeEmbed(frozen), same(frozen));
    });

    test('refuses a key that is not a string', () {
      expect(
        () => freezeEmbed({
          'k': {1: 'a'},
        }),
        throwsArgumentError,
      );
    });
  });

  group('sameEmbed', () {
    test('ignores key order, compares bytes by content', () {
      final a = {
        'x': 1,
        'y': [
          Uint8List.fromList([1, 2]),
        ],
      };
      final b = {
        'y': [
          Uint8List.fromList([1, 2]),
        ],
        'x': 1,
      };
      expect(sameEmbed(a, b), isTrue);
      expect(hashEmbed(a), hashEmbed(b));
      expect(
        sameEmbed({
          'y': Uint8List.fromList([1, 2]),
        }, {
          'y': [1, 2],
        }),
        isFalse,
      );
      expect(sameEmbed({'x': 1}, {'x': 2}), isFalse);
      expect(sameEmbed({'x': 1}, {'x': 1, 'y': 1}), isFalse);
      expect(
        sameEmbed({
          'x': [1],
        }, {
          'x': [1, 2],
        }),
        isFalse,
      );
    });
  });
}
