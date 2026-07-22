import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/widgets/markdown_shortcuts.dart';

MarkdownShortcut byTooltip(String tooltip) =>
    kMarkdownShortcuts.firstWhere((s) => s.tooltip == tooltip);

TextEditingValue empty() => TextEditingValue.empty;

TextEditingValue withCaret(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

void main() {
  group('line-prefix shortcuts', () {
    test('heading on empty text inserts the prefix (no RangeError)', () {
      final result = byTooltip('Heading 1').apply(empty());
      expect(result.text, '# ');
      expect(result.selection.baseOffset, 2);
    });

    test('heading at the very start of non-empty text', () {
      final result = byTooltip('Heading 2').apply(withCaret('title', 0));
      expect(result.text, '## title');
      expect(result.selection.baseOffset, 3); // after "## "
    });

    test('heading prefixes the caret line, not the whole document', () {
      // Caret on the second line ("world"), offset 6.
      final result = byTooltip('Heading 3').apply(withCaret('hello\nworld', 6));
      expect(result.text, 'hello\n### world');
    });

    test('bullet list on empty text', () {
      expect(byTooltip('Bullet list').apply(empty()).text, '- ');
    });
  });

  group('wrap shortcuts', () {
    test('bold with no selection sits between the markers', () {
      final result = byTooltip('Bold').apply(empty());
      expect(result.text, '****');
      expect(result.selection.baseOffset, 2);
      expect(result.selection.extentOffset, 2);
    });

    test('bold wraps the current selection', () {
      final result = byTooltip('Bold').apply(
        const TextEditingValue(
          text: 'word',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
      );
      expect(result.text, '**word**');
      expect(result.selection.baseOffset, 2);
      expect(result.selection.extentOffset, 6);
    });
  });

  group('link-like shortcuts', () {
    test('image drops the caret between the parentheses', () {
      final result = byTooltip('Image').apply(empty());
      expect(result.text, '![]()');
      // caret between '(' and ')'
      expect(result.selection.baseOffset, 4);
      expect(result.text[result.selection.baseOffset - 1], '(');
      expect(result.text[result.selection.baseOffset], ')');
    });

    test('link uses the selection as the label', () {
      final result = byTooltip('Link').apply(
        const TextEditingValue(
          text: 'site',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
      );
      expect(result.text, '[site]()');
      expect(result.selection.baseOffset, 7); // inside ()
    });
  });
}
