import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeTextDelta', () {
    test('returns null for equal strings', () {
      expect(computeTextDelta('hello', 'hello'), isNull);
    });

    test('detects an insertion at the caret', () {
      expect(
        computeTextDelta('hello world', 'hello brave world'),
        const TextDelta(index: 6, deleted: 0, inserted: 'brave '),
      );
    });

    test('detects a deletion', () {
      expect(
        computeTextDelta('hello brave world', 'hello world'),
        const TextDelta(index: 6, deleted: 6, inserted: ''),
      );
    });

    test('detects a replacement (paste over selection)', () {
      expect(
        computeTextDelta('hello world', 'hello dart'),
        const TextDelta(index: 6, deleted: 5, inserted: 'dart'),
      );
    });

    test('handles insertion at the start and at the end', () {
      expect(
        computeTextDelta('world', 'hello world'),
        const TextDelta(index: 0, deleted: 0, inserted: 'hello '),
      );
      expect(
        computeTextDelta('hello', 'hello world'),
        const TextDelta(index: 5, deleted: 0, inserted: ' world'),
      );
    });

    test('handles repeated characters (ambiguous trim)', () {
      // "aa" -> "aaa": any single-'a' insertion is equivalent.
      final delta = computeTextDelta('aa', 'aaa')!;
      expect(delta.deleted, 0);
      expect(delta.inserted, 'a');
    });

    test('anchors an ambiguous insertion to the caret', () {
      // Enter pressed *before* an existing '\n' (as between the two lines of
      // a code fence). Without the caret, greedy prefix trimming slides the
      // insertion past the caret to index 8, attaching the newline to the
      // wrong side; with the caret (offset 8, after the inserted '\n') the
      // edit is recorded where the user actually is.
      const before = '```dart\n```';
      const after = '```dart\n\n```';
      expect(
        computeTextDelta(before, after),
        const TextDelta(index: 8, deleted: 0, inserted: '\n'),
      );
      expect(
        computeTextDelta(before, after, caret: 8),
        const TextDelta(index: 7, deleted: 0, inserted: '\n'),
      );
    });

    test('anchors an ambiguous deletion to the caret', () {
      // Backspace removing the *first* of two 'a's: caret ends at 1.
      expect(
        computeTextDelta('baab', 'bab', caret: 1),
        const TextDelta(index: 1, deleted: 1, inserted: ''),
      );
    });

    test('a caret leaves an unambiguous edit unchanged', () {
      expect(
        computeTextDelta('hello world', 'hello brave world', caret: 12),
        const TextDelta(index: 6, deleted: 0, inserted: 'brave '),
      );
    });

    test('never splits a surrogate pair between kept and replaced regions', () {
      // The two emoji share the high surrogate: a naive trim would keep it
      // and replace only the low surrogate, producing lone-surrogate ops.
      final delta = computeTextDelta('🌐', '🌏')!;
      expect(delta.index, 0);
      expect(delta.deleted, 2);
      expect(delta.inserted, '🌏');
    });

    test('keeps whole emoji when appending after one', () {
      final delta = computeTextDelta('🌐', '🌐a')!;
      expect(delta, const TextDelta(index: 2, deleted: 0, inserted: 'a'));
    });
  });

  group('mapOffsetThroughDelta', () {
    const delta = TextDelta(index: 3, deleted: 2, inserted: 'xyz');

    test('offsets before the edit are unchanged', () {
      expect(mapOffsetThroughDelta(0, delta), 0);
      expect(mapOffsetThroughDelta(3, delta), 3);
    });

    test('offsets inside the replaced region snap to the insertion end', () {
      expect(mapOffsetThroughDelta(4, delta), 6);
      expect(mapOffsetThroughDelta(5, delta), 6);
    });

    test('offsets after the edit shift by the length difference', () {
      expect(mapOffsetThroughDelta(7, delta), 8);
    });
  });
}
