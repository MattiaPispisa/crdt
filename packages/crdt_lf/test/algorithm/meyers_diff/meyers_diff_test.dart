import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('myersDiff', () {
    group('segments result', () {
      test('identical strings', () {
        final result = myersDiff('hello', 'hello');
        expect(result.length, 1);
        expect(
          result[0],
          const DiffSegment(
            op: DiffOp.equal,
            text: 'hello',
            oldStart: 0,
            oldEnd: 5,
            newStart: 0,
            newEnd: 5,
          ),
        );
      });

      test('insert only', () {
        final result = myersDiff('', 'abc');
        expect(result, [
          const DiffSegment(
            op: DiffOp.insert,
            text: 'abc',
            oldStart: 0,
            oldEnd: 0,
            newStart: 0,
            newEnd: 3,
          ),
        ]);
      });

      test('remove only', () {
        final result = myersDiff('abc', '');
        expect(result, [
          const DiffSegment(
            op: DiffOp.remove,
            text: 'abc',
            oldStart: 0,
            oldEnd: 3,
            newStart: 0,
            newEnd: 0,
          ),
        ]);
      });

      test('simple substitution', () {
        final result = myersDiff('a', 'b');
        expect(result, const [
          DiffSegment(
            op: DiffOp.remove,
            text: 'a',
            oldStart: 0,
            oldEnd: 1,
            newStart: 0,
            newEnd: 0,
          ),
          DiffSegment(
            op: DiffOp.insert,
            text: 'b',
            oldStart: 1,
            oldEnd: 1,
            newStart: 0,
            newEnd: 1,
          ),
        ]);
      });

      test('common prefix and suffix', () {
        final result = myersDiff('abcxxxdef', 'abcyyydef');
        expect(result, const [
          DiffSegment(
            op: DiffOp.equal,
            text: 'abc',
            oldStart: 0,
            oldEnd: 3,
            newStart: 0,
            newEnd: 3,
          ),
          DiffSegment(
            op: DiffOp.remove,
            text: 'xxx',
            oldStart: 3,
            oldEnd: 6,
            newStart: 3,
            newEnd: 3,
          ),
          DiffSegment(
            op: DiffOp.insert,
            text: 'yyy',
            oldStart: 6,
            oldEnd: 6,
            newStart: 3,
            newEnd: 6,
          ),
          DiffSegment(
            op: DiffOp.equal,
            text: 'def',
            oldStart: 6,
            oldEnd: 9,
            newStart: 6,
            newEnd: 9,
          ),
        ]);
      });

      test('large complex unicode and multi-line text', () {
        const oldText = 'Line1: Hello world!\n'
            'Line2: The quick brown fox jumps over the lazy dog.\n'
            'Line3: Numbers 1234567890.\n'
            'Line4: Accents àèìòù and emoji 😀😎.\n'
            'Line5: End.\n';

        const newText = 'Line1: Hello brave new world!\n'
            'Line2: The quick brown fox leaped over the lazy 🐶.\n'
            'LineX: Inserted brand-new line.\n'
            'Line3: Numbers 1234567890 and hex 0xDEADBEEF.\n'
            'Line4: Accents àèìòù and emoji 😀🤖.\n'
            'Line5: End!!!\n';

        final diffs = myersDiff(oldText, newText);

        // Verify we have all three types of operations
        expect(diffs.any((s) => s.op == DiffOp.equal), true);
        expect(diffs.any((s) => s.op == DiffOp.insert), true);
        expect(diffs.any((s) => s.op == DiffOp.remove), true);

        // Reconstruct newText from inserts and equals
        final reconstructed = diffs
            .where((s) => s.op == DiffOp.insert || s.op == DiffOp.equal)
            .map((s) => s.text)
            .join();
        expect(reconstructed, newText);

        // Verify some key insertions are present
        final allInserts =
            diffs.where((s) => s.op == DiffOp.insert).map((s) => s.text).join();
        expect(allInserts.contains('brave ne'), true);
        expect(allInserts.contains('🐶'), true);
        expect(allInserts.contains('🤖'), true);
        expect(allInserts.contains('LineX:'), true);

        // Verify some key removals are present
        final allRemoves =
            diffs.where((s) => s.op == DiffOp.remove).map((s) => s.text).join();
        expect(allRemoves.contains('jum'), true);
        expect(allRemoves.contains('😎'), true);

        // Verify all indices are consistent
        for (final seg in diffs) {
          expect(seg.oldStart >= 0, true);
          expect(seg.oldEnd >= seg.oldStart, true);
          expect(seg.newStart >= 0, true);
          expect(seg.newEnd >= seg.newStart, true);

          if (seg.op == DiffOp.equal) {
            expect(seg.oldEnd - seg.oldStart, seg.newEnd - seg.newStart);
            expect(seg.text.length, seg.oldEnd - seg.oldStart);
          } else if (seg.op == DiffOp.insert) {
            expect(seg.oldEnd, seg.oldStart);
            expect(seg.text.length, seg.newEnd - seg.newStart);
          } else if (seg.op == DiffOp.remove) {
            expect(seg.newEnd, seg.newStart);
            expect(seg.text.length, seg.oldEnd - seg.oldStart);
          }
        }
      });
    });

    group('segments ordering', () {
      test('segments are always ordered by indices', () {
        const oldText = 'The quick brown fox jumps over the lazy dog.';
        const newText = 'The quick red fox leaped over the lazy cat.';

        final diffs = myersDiff(oldText, newText);

        // Verify segments are ordered by oldStart
        for (var i = 1; i < diffs.length; i++) {
          final prev = diffs[i - 1];
          final curr = diffs[i];

          // Current segment's oldStart should be >= previous segment's oldEnd
          expect(
            curr.oldStart >= prev.oldEnd,
            true,
            reason: 'Segment $i oldStart (${curr.oldStart}) should be >= '
                'previous oldEnd (${prev.oldEnd})',
          );

          // Current segment's newStart should be >= previous segment's newEnd
          expect(
            curr.newStart >= prev.newStart,
            true,
            reason: 'Segment $i newStart (${curr.newStart}) should be >= '
                'previous newStart (${prev.newStart})',
          );
        }
      });

      test('segments ordering with complex text', () {
        const oldText = 'Line1: Hello world!\n'
            'Line2: The quick brown fox jumps over the lazy dog.\n'
            'Line3: Numbers 1234567890.\n'
            'Line4: Accents àèìòù and emoji 😀😎.\n'
            'Line5: End.\n';

        const newText = 'Line1: Hello brave new world!\n'
            'Line2: The quick brown fox leaped over the lazy 🐶.\n'
            'LineX: Inserted brand-new line.\n'
            'Line3: Numbers 1234567890 and hex 0xDEADBEEF.\n'
            'Line4: Accents àèìòù and emoji 😀🤖.\n'
            'Line5: End!!!\n';

        final diffs = myersDiff(oldText, newText);

        var prevOldEnd = 0;
        var prevNewEnd = 0;

        for (var i = 0; i < diffs.length; i++) {
          final seg = diffs[i];

          // oldStart should be >= previous oldEnd
          expect(
            seg.oldStart >= prevOldEnd,
            true,
            reason: 'Segment $i: oldStart (${seg.oldStart}) should be >= '
                'previous oldEnd ($prevOldEnd). Segment: $seg',
          );

          // newStart should be >= previous newEnd
          expect(
            seg.newStart >= prevNewEnd,
            true,
            reason: 'Segment $i: newStart (${seg.newStart}) should be >= '
                'previous newEnd ($prevNewEnd). Segment: $seg',
          );

          prevOldEnd = seg.oldEnd;
          prevNewEnd = seg.newEnd;
        }
      });
    });

    group('segments contiguous', () {
      test('mixed edits', () {
        final result = myersDiff('ABCABBA', 'CBABAC');

        // Verify we have some inserts, removes, and potentially equals
        expect(result.isNotEmpty, true);
        expect(result.any((s) => s.op == DiffOp.insert), true);
        expect(result.any((s) => s.op == DiffOp.remove), true);

        // Verify all text from inserts and equals matches newText
        final insertsAndEquals = result
            .where((s) => s.op == DiffOp.insert || s.op == DiffOp.equal)
            .map((s) => s.text)
            .join();
        expect(insertsAndEquals, 'CBABAC');

        // Verify indices are consistent
        for (final seg in result) {
          expect(seg.oldStart >= 0, true);
          expect(seg.oldEnd >= seg.oldStart, true);
          expect(seg.newStart >= 0, true);
          expect(seg.newEnd >= seg.newStart, true);

          if (seg.op == DiffOp.equal) {
            expect(seg.oldEnd - seg.oldStart, seg.newEnd - seg.newStart);
          } else if (seg.op == DiffOp.insert) {
            expect(seg.oldEnd, seg.oldStart);
          } else if (seg.op == DiffOp.remove) {
            expect(seg.newEnd, seg.newStart);
          }
        }
      });

      test('segments are contiguous', () {
        const oldText = 'ABCDEFGH';
        const newText = 'AXCXEFXH';

        final diffs = myersDiff(oldText, newText);

        // Verify segments cover all of oldText and newText without gaps
        var expectedOldPos = 0;
        var expectedNewPos = 0;

        for (final seg in diffs) {
          expect(
            seg.oldStart,
            expectedOldPos,
            reason: 'Segment oldStart should be contiguous',
          );
          expect(
            seg.newStart,
            expectedNewPos,
            reason: 'Segment newStart should be contiguous',
          );

          expectedOldPos = seg.oldEnd;
          expectedNewPos = seg.newEnd;
        }

        // After all segments, we should have covered the entire texts
        expect(expectedOldPos, oldText.length);
        expect(expectedNewPos, newText.length);
      });

      test('segments are contiguous with only inserts', () {
        const oldText = 'ABC';
        const newText = 'AXBXC';

        final diffs = myersDiff(oldText, newText);

        _verifyContiguous(diffs, oldText.length, newText.length);
      });

      test('segments are contiguous with only removes', () {
        const oldText = 'AXBXC';
        const newText = 'ABC';

        final diffs = myersDiff(oldText, newText);

        _verifyContiguous(diffs, oldText.length, newText.length);
      });

      test('segments are contiguous with empty strings', () {
        const oldText = '';
        const newText = 'Hello';

        final diffs1 = myersDiff(oldText, newText);
        _verifyContiguous(diffs1, oldText.length, newText.length);

        final diffs2 = myersDiff(newText, oldText);
        _verifyContiguous(diffs2, newText.length, oldText.length);
      });

      test('segments are contiguous with complex multiline text', () {
        const oldText = 'Line 1\nLine 2\nLine 3\n';
        const newText = 'Line 1\nModified Line 2\nLine 3\nLine 4\n';

        final diffs = myersDiff(oldText, newText);

        _verifyContiguous(diffs, oldText.length, newText.length);
      });

      test('segments are contiguous with unicode', () {
        const oldText = 'Hello 🌍 World 🎉';
        const newText = 'Hello 🌎 Beautiful 🌟 World';

        final diffs = myersDiff(oldText, newText);

        _verifyContiguous(diffs, oldText.length, newText.length);
      });
    });
  });

  group('diff application', () {
    test('apply diff operations to reconstruct new text', () {
      const oldText = 'The quick brown fox jumps over the lazy dog.';
      const newText = 'The quick red fox leaped over the lazy cat.';

      final diffs = myersDiff(oldText, newText);

      // Apply the diff operations to oldText to get newText
      final result = _applyDiff(oldText, diffs);
      expect(result, newText);
    });

    test('apply diff operations with complex edits', () {
      const oldText = 'Hello world!\nThis is a test.\nGoodbye!';
      const newText = 'Hello beautiful world!\nThis is awesome.\nSee you!';

      final diffs = myersDiff(oldText, newText);

      // Apply the diff operations to oldText to get newText
      final result = _applyDiff(oldText, diffs);
      expect(result, newText);
    });

    test('apply diff operations with unicode', () {
      const oldText = 'Emoji test: 😀😎🎉';
      const newText = 'Emoji test: 😀🤖🎊🎉';

      final diffs = myersDiff(oldText, newText);

      // Apply the diff operations to oldText to get newText
      final result = _applyDiff(oldText, diffs);
      expect(result, newText);
    });
  });
}

/// Verify that segments are contiguous with no gaps or overlaps.
void _verifyContiguous(List<DiffSegment> diffs, int oldLength, int newLength) {
  if (diffs.isEmpty) {
    expect(oldLength, 0);
    expect(newLength, 0);
    return;
  }

  var expectedOldPos = 0;
  var expectedNewPos = 0;

  for (var i = 0; i < diffs.length; i++) {
    final seg = diffs[i];

    expect(
      seg.oldStart,
      expectedOldPos,
      reason: 'Segment $i: oldStart (${seg.oldStart}) should equal '
          'expected position ($expectedOldPos). No gaps allowed.',
    );
    expect(
      seg.newStart,
      expectedNewPos,
      reason: 'Segment $i: newStart (${seg.newStart}) should equal '
          'expected position ($expectedNewPos). No gaps allowed.',
    );

    expectedOldPos = seg.oldEnd;
    expectedNewPos = seg.newEnd;
  }

  // After all segments, we should have covered the entire texts
  expect(
    expectedOldPos,
    oldLength,
    reason: 'All segments should cover entire oldText',
  );
  expect(
    expectedNewPos,
    newLength,
    reason: 'All segments should cover entire newText',
  );
}

/// Apply diff operations to oldText to reconstruct newText.
/// Start with oldText and apply insert/remove operations in reverse order.
String _applyDiff(String oldText, List<DiffSegment> diffs) {
  var result = oldText;

  // Process segments in reverse order to avoid index shifting
  for (var i = diffs.length - 1; i >= 0; i--) {
    final seg = diffs[i];

    switch (seg.op) {
      case DiffOp.equal:
        // Nothing to do, text is already correct
        break;
      case DiffOp.insert:
        // Insert new text at oldStart position
        result = result.substring(0, seg.oldStart) +
            seg.text +
            result.substring(seg.oldStart);
        break;
      case DiffOp.remove:
        // Remove text from oldStart to oldEnd
        result =
            result.substring(0, seg.oldStart) + result.substring(seg.oldEnd);
        break;
    }
  }

  return result;
}
