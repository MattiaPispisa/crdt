import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';
import 'package:greyhound_markdown_client/src/widgets/markdown_shortcuts.dart';

import 'helpers/localized_app.dart';

/// The text shortcut named [label]. Undo and redo are in the same list but
/// are not text transforms, so they are not reachable through this.
MarkdownTextShortcut byLabel(MarkdownShortcutLabel label) =>
    kMarkdownShortcuts.firstWhere((s) => s.label == label)
        as MarkdownTextShortcut;

TextEditingValue empty() => TextEditingValue.empty;

TextEditingValue withCaret(String text, int offset) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset),
);

void main() {
  group('line-prefix shortcuts', () {
    test('heading on empty text inserts the prefix (no RangeError)', () {
      final result = byLabel(MarkdownShortcutLabel.heading1).apply(empty());
      expect(result.text, '# ');
      expect(result.selection.baseOffset, 2);
    });

    test('heading at the very start of non-empty text', () {
      final result = byLabel(MarkdownShortcutLabel.heading2).apply(withCaret('title', 0));
      expect(result.text, '## title');
      expect(result.selection.baseOffset, 3); // after "## "
    });

    test('heading prefixes the caret line, not the whole document', () {
      // Caret on the second line ("world"), offset 6.
      final result = byLabel(MarkdownShortcutLabel.heading3).apply(withCaret('hello\nworld', 6));
      expect(result.text, 'hello\n### world');
    });

    test('bullet list on empty text', () {
      expect(byLabel(MarkdownShortcutLabel.bulletList).apply(empty()).text, '- ');
    });
  });

  group('wrap shortcuts', () {
    test('bold with no selection sits between the markers', () {
      final result = byLabel(MarkdownShortcutLabel.bold).apply(empty());
      expect(result.text, '****');
      expect(result.selection.baseOffset, 2);
      expect(result.selection.extentOffset, 2);
    });

    test('bold wraps the current selection', () {
      final result = byLabel(MarkdownShortcutLabel.bold).apply(
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
      final result = byLabel(MarkdownShortcutLabel.image).apply(empty());
      expect(result.text, '![]()');
      // caret between '(' and ')'
      expect(result.selection.baseOffset, 4);
      expect(result.text[result.selection.baseOffset - 1], '(');
      expect(result.text[result.selection.baseOffset], ')');
    });

    test('link uses the selection as the label', () {
      final result = byLabel(MarkdownShortcutLabel.link).apply(
        const TextEditingValue(
          text: 'site',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
      );
      expect(result.text, '[site]()');
      expect(result.selection.baseOffset, 7); // inside ()
    });
  });

  group('key bindings', () {
    late AppL10n l10n;

    setUpAll(() async {
      l10n = await englishL10n();
    });

    test('the tooltip carries the chord in the platform notation', () {
      final bold = byLabel(MarkdownShortcutLabel.bold);
      expect(bold.tooltipFor(l10n, TargetPlatform.macOS), 'Bold (⌘B)');
      expect(bold.tooltipFor(l10n, TargetPlatform.windows), 'Bold (Ctrl+B)');
    });

    test('an unbound action keeps its plain tooltip', () {
      expect(
        byLabel(
          MarkdownShortcutLabel.heading1,
        ).tooltipFor(l10n, TargetPlatform.macOS),
        'Heading 1',
      );
      expect(byLabel(MarkdownShortcutLabel.heading1).binding, isNull);
    });

    test('the modifier is Meta on Apple platforms and Control elsewhere', () {
      final binding = byLabel(MarkdownShortcutLabel.link).binding!;
      final apple = binding.activator(TargetPlatform.macOS) as SingleActivator;
      expect(apple.meta, isTrue);
      expect(apple.control, isFalse);
      expect(apple.trigger, LogicalKeyboardKey.keyK);

      final other =
          binding.activator(TargetPlatform.windows) as SingleActivator;
      expect(other.control, isTrue);
      expect(other.meta, isFalse);
    });
  });
}
