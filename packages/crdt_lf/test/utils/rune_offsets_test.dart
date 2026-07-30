import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  // 'a😀b': a=1 unit, 😀=2 units (U+1F600), b=1 unit → 4 units, 3 runes.
  const emoji = 'a😀b';
  final loneHigh = String.fromCharCode(0xD83D);
  final loneLow = String.fromCharCode(0xDE00);

  group('RuneOffsets', () {
    group('length', () {
      test('counts a surrogate pair as one rune', () {
        expect(emoji.length, 4);
        expect(RuneOffsets.length(emoji), 3);
      });

      test('counts an unpaired surrogate as one rune', () {
        expect(RuneOffsets.length(loneHigh), 1);
        expect(RuneOffsets.length('$loneLow$loneHigh'), 2);
      });

      test('is zero for the empty string', () {
        expect(RuneOffsets.length(''), 0);
      });
    });

    group('utf16Offset', () {
      test('maps each rune boundary to its code-unit offset', () {
        expect(RuneOffsets.utf16Offset(emoji, 0), 0);
        expect(RuneOffsets.utf16Offset(emoji, 1), 1);
        expect(RuneOffsets.utf16Offset(emoji, 2), 3);
        expect(RuneOffsets.utf16Offset(emoji, 3), 4);
      });

      test('clamps out-of-range indices to the ends', () {
        expect(RuneOffsets.utf16Offset(emoji, -1), 0);
        expect(RuneOffsets.utf16Offset(emoji, 99), emoji.length);
      });
    });

    group('runeIndex', () {
      test('maps each code-unit boundary back to its rune index', () {
        expect(RuneOffsets.runeIndex(emoji, 0), 0);
        expect(RuneOffsets.runeIndex(emoji, 1), 1);
        expect(RuneOffsets.runeIndex(emoji, 3), 2);
        expect(RuneOffsets.runeIndex(emoji, 4), 3);
      });

      test('resolves an offset inside a pair to the containing rune', () {
        // Offset 2 splits the emoji: it belongs to the rune starting at 1.
        expect(RuneOffsets.runeIndex(emoji, 2), 1);
      });

      test('clamps out-of-range offsets to the ends', () {
        expect(RuneOffsets.runeIndex(emoji, -1), 0);
        expect(RuneOffsets.runeIndex(emoji, 99), 3);
      });
    });

    test('the two conversions round-trip on rune boundaries', () {
      const text = 'a😀b🎉c';
      for (var i = 0; i <= RuneOffsets.length(text); i++) {
        expect(
          RuneOffsets.runeIndex(text, RuneOffsets.utf16Offset(text, i)),
          i,
        );
      }
    });

    test('offsets and indices coincide for all-BMP text', () {
      const text = 'hello, wörld';
      expect(RuneOffsets.length(text), text.length);
      for (var i = 0; i <= text.length; i++) {
        expect(RuneOffsets.utf16Offset(text, i), i);
        expect(RuneOffsets.runeIndex(text, i), i);
      }
    });
  });
}
