import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('Wtf8', () {
    group('is byte-identical to utf8 for well-formed strings', () {
      const wellFormed = <String>[
        '',
        'hello world',
        'Ascii 123 !@#',
        'accénti àèìòù',
        '日本語のテキスト',
        'emoji 😀 mixed 🎉 text',
        'examp𝕝e', // mathematical alphanumerics (non-BMP)
        '𐐷', // Deseret (non-BMP)
        'replacement � char', // U+FFFD is itself a valid BMP scalar
      ];

      for (final s in wellFormed) {
        test('"$s"', () {
          expect(Wtf8.encode(s), equals(utf8.encode(s)));
        });
      }
    });

    test('round-trips well-formed strings losslessly', () {
      for (final s in ['', 'a', '😀', 'a😀b', '日本😀語']) {
        expect(Wtf8.decode(Wtf8.encode(s)), equals(s));
      }
    });

    test('round-trips a lone high surrogate losslessly', () {
      final lone = String.fromCharCode(0xD83D); // high surrogate of 😀
      final encoded = Wtf8.encode(lone);
      // 3-byte ED xx xx sequence (what strict utf8 would corrupt to U+FFFD).
      expect(encoded, equals(Uint8List.fromList([0xED, 0xA0, 0xBD])));
      final decoded = Wtf8.decode(encoded);
      expect(decoded.codeUnits, equals([0xD83D]));
    });

    test('round-trips a lone low surrogate losslessly', () {
      final lone = String.fromCharCode(0xDE00); // low surrogate of 😀
      expect(Wtf8.decode(Wtf8.encode(lone)).codeUnits, equals([0xDE00]));
    });

    test('two independently-encoded halves rejoin into the scalar', () {
      // Reproduces the Fugue path: a surrogate pair split across two elements,
      // each encoded on its own, then concatenated back together.
      final high = String.fromCharCode(0xD83D);
      final low = String.fromCharCode(0xDE00);
      final joined = Wtf8.decode(Wtf8.encode(high)) + //
          Wtf8.decode(Wtf8.encode(low));
      expect(joined, equals('😀'));
    });

    test('decodes bytes produced by the standard utf8 encoder', () {
      // Backward compatibility: already-persisted data was written with utf8.
      const s = 'legacy 😀 data 日本語';
      expect(Wtf8.decode(Uint8List.fromList(utf8.encode(s))), equals(s));
    });

    test('throws on a truncated multi-byte sequence', () {
      expect(
        () => Wtf8.decode(Uint8List.fromList([0xF0, 0x9F])),
        throwsFormatException,
      );
    });
  });
}
