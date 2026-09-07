import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';

/// A key binding whose primary modifier follows the platform: ⌘ on Apple
/// platforms, Ctrl everywhere else.
///
/// Used by the markdown shortcuts below and by the undo/redo chords in
/// `EditorToolbar`, so a chord reads the same wherever the editor shows one.
class EditorShortcutBinding {
  /// Binds [trigger], optionally with Shift, to the platform modifier.
  const EditorShortcutBinding(this.trigger, {this.shift = false});

  /// The key pressed alongside the modifiers.
  final LogicalKeyboardKey trigger;

  /// Whether Shift is part of the chord.
  final bool shift;

  static bool _isApple(TargetPlatform platform) =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

  /// The activator to register for [platform].
  ShortcutActivator activator(TargetPlatform platform) => SingleActivator(
    trigger,
    control: !_isApple(platform),
    meta: _isApple(platform),
    shift: shift,
  );

  /// The chord as the user reads it: `⇧⌘K` on Apple platforms, `Ctrl+Shift+K`
  /// elsewhere.
  String label(TargetPlatform platform) {
    final key = trigger.keyLabel;
    if (_isApple(platform)) {
      return '${shift ? '⇧' : ''}⌘$key';
    }
    return 'Ctrl+${shift ? 'Shift+' : ''}$key';
  }
}

/// What a shortcut acts on: the field the editor is bound to, and the room's
/// undo history.
///
/// Both are passed to every shortcut, so the toolbar and the key bindings can
/// treat them all the same — a formatting action and an undo are one list.
typedef EditorShortcutTarget = ({
  TextEditingController controller,
  CRDTUndoManager undo,
});

/// Which action a [MarkdownShortcut] is, and so which tooltip it shows.
///
/// A key rather than the text itself: [kMarkdownShortcuts] is a top-level
/// `const` list, built long before there is a [BuildContext] to read the
/// translations from.
enum MarkdownShortcutLabel {
  /// Take back the last edit.
  undo,

  /// Write back the edit that was taken away.
  redo,

  /// Bold the selection.
  bold,

  /// Italicize the selection.
  italic,

  /// Strike the selection through.
  strikethrough,

  /// Mark the selection as code.
  inlineCode,

  /// Turn the line into a top-level heading.
  heading1,

  /// Turn the line into a second-level heading.
  heading2,

  /// Turn the line into a third-level heading.
  heading3,

  /// Turn the line into a block quote.
  quote,

  /// Turn the line into a list item.
  bulletList,

  /// Wrap the selection in a link.
  link,

  /// Wrap the selection in an image.
  image;

  /// How this action is named in [l10n].
  String text(AppL10n l10n) {
    return switch (this) {
      MarkdownShortcutLabel.undo => l10n.shortcutUndo,
      MarkdownShortcutLabel.redo => l10n.shortcutRedo,
      MarkdownShortcutLabel.bold => l10n.shortcutBold,
      MarkdownShortcutLabel.italic => l10n.shortcutItalic,
      MarkdownShortcutLabel.strikethrough => l10n.shortcutStrikethrough,
      MarkdownShortcutLabel.inlineCode => l10n.shortcutInlineCode,
      MarkdownShortcutLabel.heading1 => l10n.shortcutHeading1,
      MarkdownShortcutLabel.heading2 => l10n.shortcutHeading2,
      MarkdownShortcutLabel.heading3 => l10n.shortcutHeading3,
      MarkdownShortcutLabel.quote => l10n.shortcutQuote,
      MarkdownShortcutLabel.bulletList => l10n.shortcutBulletList,
      MarkdownShortcutLabel.link => l10n.shortcutLink,
      MarkdownShortcutLabel.image => l10n.shortcutImage,
    };
  }
}

/// A single action the editor toolbar shows as a button.
///
/// The toolbar iterates [kMarkdownShortcuts], asks each one whether it can run
/// ([isEnabled]) and, on tap, tells it to ([run]). Most of them are
/// [MarkdownTextShortcut]s, which rewrite the field's value; undo and redo
/// write to the document instead. The toolbar does not know the difference.
abstract class MarkdownShortcut {
  /// Const base constructor.
  const MarkdownShortcut({
    required this.icon,
    required this.label,
    this.binding,
  });

  /// The button glyph.
  final IconData icon;

  /// Which action this is; the tooltip is its translation.
  final MarkdownShortcutLabel label;

  /// The keyboard chord that also triggers this action, if it has one.
  final EditorShortcutBinding? binding;

  /// Performs this shortcut on [target].
  void run(EditorShortcutTarget target);

  /// Whether running it right now would do anything.
  ///
  /// A shortcut that always has something to do keeps this default; undo and
  /// redo answer from their stack, which is what greys their buttons out.
  bool isEnabled(EditorShortcutTarget target) => true;

  /// The translated [label], with the key chord appended when [binding] is
  /// set.
  String tooltipFor(AppL10n l10n, TargetPlatform platform) {
    final text = label.text(l10n);
    final binding = this.binding;
    if (binding == null) {
      return text;
    }
    return '$text (${binding.label(platform)})';
  }
}

/// A shortcut that is a pure transform over the field's [TextEditingValue]:
/// given the current text and selection it returns the text and caret to show
/// next.
///
/// Running one assigns the result back to the controller — which the CRDT text
/// binding then turns into the corresponding document edit.
abstract class MarkdownTextShortcut extends MarkdownShortcut {
  /// Const base constructor.
  const MarkdownTextShortcut({
    required super.icon,
    required super.label,
    super.binding,
  });

  /// Returns the new editing value (text + caret/selection) after applying
  /// this shortcut to [value].
  TextEditingValue apply(TextEditingValue value);

  @override
  void run(EditorShortcutTarget target) =>
      target.controller.value = apply(target.controller.value);
}

/// Which way a [_UndoManagerShortcut] moves the history.
enum _UndoDirection { undo, redo }

/// Takes back the last edit, or writes it back.
///
/// It does not touch the controller: it asks [CRDTUndoManager] to write the
/// opposite operation, and the text binding adopts that like any other change.
class _UndoManagerShortcut extends MarkdownShortcut {
  const _UndoManagerShortcut({
    required super.icon,
    required super.label,
    required super.binding,
    required this.direction,
  });

  /// Which way this one moves the history.
  final _UndoDirection direction;

  @override
  bool isEnabled(EditorShortcutTarget target) => switch (direction) {
    _UndoDirection.undo => target.undo.canUndo,
    _UndoDirection.redo => target.undo.canRedo,
  };

  @override
  void run(EditorShortcutTarget target) {
    switch (direction) {
      case _UndoDirection.undo:
        target.undo.undo();
      case _UndoDirection.redo:
        target.undo.redo();
    }
  }
}

/// The bindings of every shortcut that declares one, each running itself
/// against [target]. Ready to hand to a [CallbackShortcuts].
///
/// The undo and redo chords are in here with the rest, which is what puts them
/// **below** `DefaultTextEditingShortcuts`: ⌘Z then reaches the document's
/// history instead of the text field's own, and the field's would replay a
/// plain text diff and take back what other peers wrote.
Map<ShortcutActivator, VoidCallback> markdownShortcutBindings(
  EditorShortcutTarget target,
  TargetPlatform platform,
) {
  return {
    for (final shortcut in kMarkdownShortcuts)
      if (shortcut.binding != null)
        shortcut.binding!.activator(platform): () {
          if (shortcut.isEnabled(target)) {
            shortcut.run(target);
          }
        },
  };
}

/// The ordered set of shortcuts rendered by the editor toolbar.
const List<MarkdownShortcut> kMarkdownShortcuts = [
  _UndoManagerShortcut(
    icon: Icons.undo,
    label: MarkdownShortcutLabel.undo,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyZ),
    direction: _UndoDirection.undo,
  ),
  _UndoManagerShortcut(
    icon: Icons.redo,
    label: MarkdownShortcutLabel.redo,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyZ, shift: true),
    direction: _UndoDirection.redo,
  ),
  _WrapShortcut(
    icon: Icons.format_bold,
    label: MarkdownShortcutLabel.bold,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyB),
    marker: '**',
  ),
  _WrapShortcut(
    icon: Icons.format_italic,
    label: MarkdownShortcutLabel.italic,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyI),
    marker: '*',
  ),
  _WrapShortcut(
    icon: Icons.strikethrough_s,
    label: MarkdownShortcutLabel.strikethrough,
    marker: '~~',
  ),
  _WrapShortcut(
    icon: Icons.code,
    label: MarkdownShortcutLabel.inlineCode,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyE),
    marker: '`',
  ),
  _LinePrefixShortcut(icon: Icons.title, label: MarkdownShortcutLabel.heading1, prefix: '# '),
  _LinePrefixShortcut(
    icon: Icons.text_fields,
    label: MarkdownShortcutLabel.heading2,
    prefix: '## ',
  ),
  _LinePrefixShortcut(
    icon: Icons.short_text,
    label: MarkdownShortcutLabel.heading3,
    prefix: '### ',
  ),
  _LinePrefixShortcut(icon: Icons.format_quote, label: MarkdownShortcutLabel.quote, prefix: '> '),
  _LinePrefixShortcut(
    icon: Icons.format_list_bulleted,
    label: MarkdownShortcutLabel.bulletList,
    prefix: '- ',
  ),
  _LinkLikeShortcut(
    icon: Icons.link,
    label: MarkdownShortcutLabel.link,
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyK),
    open: '[',
  ),
  _LinkLikeShortcut(icon: Icons.image, label: MarkdownShortcutLabel.image, open: '!['),
];

/// The caret as an offset, defaulting to end-of-text when the field has never
/// been focused (`baseOffset < 0`), so toolbar buttons work without focus.
TextSelection _resolvedSelection(TextEditingValue value) {
  final selection = value.selection;
  if (selection.baseOffset < 0) {
    return TextSelection.collapsed(offset: value.text.length);
  }
  return selection;
}

/// Wraps the selection in [marker] on both sides (bold/italic/…). With no
/// selection, inserts `marker + marker` and drops the caret between them.
class _WrapShortcut extends MarkdownTextShortcut {
  const _WrapShortcut({
    required super.icon,
    required super.label,
    required this.marker,
    super.binding,
  });

  final String marker;

  @override
  TextEditingValue apply(TextEditingValue value) {
    final selection = _resolvedSelection(value);
    final text = value.text;
    final selected = selection.textInside(text);
    final replacement = '$marker$selected$marker';
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    // With a selection, keep it wrapped; without one, sit between the markers.
    final int base;
    final int extent;
    if (selected.isEmpty) {
      base = extent = selection.start + marker.length;
    } else {
      base = selection.start + marker.length;
      extent = base + selected.length;
    }
    return TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );
  }
}

/// Inserts [prefix] at the start of the caret's line (headings/quote/list).
class _LinePrefixShortcut extends MarkdownTextShortcut {
  const _LinePrefixShortcut({
    required super.icon,
    required super.label,
    required this.prefix,
  });

  final String prefix;

  @override
  TextEditingValue apply(TextEditingValue value) {
    final selection = _resolvedSelection(value);
    final text = value.text;
    // Start of the caret's line. Guard offset 0: `lastIndexOf` throws on a
    // negative start, which is exactly the empty-text / start-of-text case.
    final lineStart = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    final shift = prefix.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: selection.baseOffset + shift,
        extentOffset: selection.extentOffset + shift,
      ),
    );
  }
}

/// Inserts a link/image template `open + label + ']()'` and drops the caret
/// **inside the trailing `()`**, ready for the URL. Any selection becomes the
/// label text.
class _LinkLikeShortcut extends MarkdownTextShortcut {
  const _LinkLikeShortcut({
    required super.icon,
    required super.label,
    required this.open,
    super.binding,
  });

  /// The leading token: `'['` for a link, `'!['` for an image.
  final String open;

  @override
  TextEditingValue apply(TextEditingValue value) {
    final selection = _resolvedSelection(value);
    final text = value.text;
    final label = selection.textInside(text);
    const close = ']()';
    final replacement = '$open$label$close';
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    // Caret between the parentheses: one char before the closing ')'.
    final caret = selection.start + replacement.length - 1;
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
