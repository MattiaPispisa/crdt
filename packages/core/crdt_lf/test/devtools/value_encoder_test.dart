// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/devtools/value_encoder.dart';
import 'package:test/test.dart';

class _WithJson {
  @override
  String toString() => 'WithJson';

  Map<String, Object?> toJson() => {'a': 1};
}

class _Plain {
  @override
  String toString() => 'Plain';
}

void main() {
  group('encodeDevToolsValue', () {
    test('keeps scalars as they are', () {
      for (final value in [null, true, 3, 'hi', 1.5]) {
        expect(encodeDevToolsValue(value), value);
      }
    });

    test('tags NaN and the infinities', () {
      expect(encodeDevToolsValue(double.nan), {r'$t': 'double', 'v': 'NaN'});
      expect(
        encodeDevToolsValue(double.infinity),
        {r'$t': 'double', 'v': 'Infinity'},
      );
      expect(
        encodeDevToolsValue(double.negativeInfinity),
        {r'$t': 'double', 'v': '-Infinity'},
      );
    });

    test('cuts a string longer than maxString', () {
      expect(encodeDevToolsValue('abcdef', maxString: 3), {
        r'$t': 'string',
        'length': 6,
        'head': 'abc',
      });
      expect(
        (encodeDevToolsValue('ab😀', maxString: 3)! as Map)['head'],
        'ab',
      );
    });

    test('encodes a list, a set and a map', () {
      expect(encodeDevToolsValue([1, 'a']), {
        r'$t': 'list',
        'length': 2,
        'items': [1, 'a'],
      });
      expect(encodeDevToolsValue({1, 2}), {
        r'$t': 'set',
        'length': 2,
        'items': [1, 2],
      });
      expect(encodeDevToolsValue({'k': 1}), {
        r'$t': 'map',
        'length': 1,
        'entries': [
          ['k', 1],
        ],
      });
    });

    test('keeps the first maxItems items with the full length', () {
      expect(encodeDevToolsValue([1, 2, 3], maxItems: 2), {
        r'$t': 'list',
        'length': 3,
        'items': [1, 2],
      });
      expect(
        (encodeDevToolsValue({'a': 1, 'b': 2}, maxItems: 1)! as Map)['entries'],
        [
          ['a', 1],
        ],
      );
    });

    test('stops at maxDepth', () {
      expect(
        encodeDevToolsValue(
          [
            [
              [1],
            ],
            2,
          ],
          maxDepth: 2,
        ),
        {
          r'$t': 'list',
          'length': 2,
          'items': [
            {
              r'$t': 'list',
              'length': 1,
              'items': [
                {r'$t': 'more'},
              ],
            },
            2,
          ],
        },
      );
    });

    test('encodes a handler ref', () {
      expect(encodeDevToolsValue(const HandlerRef('id', 'type')), {
        r'$t': 'ref',
        'id': 'id',
        'type': 'type',
      });
    });

    test('encodes a text span and an embed span', () {
      expect(encodeDevToolsValue(RichTextSpan('hi', {'bold': true})), {
        r'$t': 'span',
        'text': 'hi',
        'attributes': {
          r'$t': 'map',
          'length': 1,
          'entries': [
            ['bold', true],
          ],
        },
        'embed': null,
      });
      expect(
        (encodeDevToolsValue(RichTextSpan.embed({'image': 'x'}))!
            as Map)['embed'],
        {
          r'$t': 'map',
          'length': 1,
          'entries': [
            ['image', 'x'],
          ],
        },
      );
    });

    test('encodes bytes as their length and a hex head', () {
      expect(encodeDevToolsValue(Uint8List.fromList([0, 15, 255])), {
        r'$t': 'bytes',
        'length': 3,
        'head': '000fff',
      });
      final long = encodeDevToolsValue(Uint8List(40))! as Map;
      expect(long['length'], 40);
      expect(long['head'], '00' * 32);
    });

    test('encodes an object, with its toJson when it has one', () {
      expect(encodeDevToolsValue(_WithJson()), {
        r'$t': 'object',
        'type': '_WithJson',
        'text': 'WithJson',
        'json': {
          r'$t': 'map',
          'length': 1,
          'entries': [
            ['a', 1],
          ],
        },
      });
      expect(encodeDevToolsValue(_Plain(), maxString: 3), {
        r'$t': 'object',
        'type': '_Plain',
        'text': 'Pla',
      });
    });
  });
}
