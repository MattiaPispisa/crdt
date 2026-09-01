import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.tooltip,
    this.binding,
  });

  /// The button glyph.
  final IconData icon;

  /// The button tooltip / semantics label.
  final String tooltip;

  /// The keyboard chord that also triggers this action, if it has one.
  final EditorShortcutBinding? binding;

  /// Performs this shortcut on [target].
  void run(EditorShortcutTarget target);

  /// Whether running it right now would do anything.
  ///
  /// A shortcut that always has something to do keeps this default; undo and
  /// redo answer from their stack, which is what greys their buttons out.
  bool isEnabled(EditorShortcutTarget target) => true;

  /// [tooltip] with the key chord appended when [binding] is set.
  String tooltipFor(TargetPlatform platform) {
    final binding = this.binding;
    if (binding == null) {
      return tooltip;
    }
    return '$tooltip (${binding.label(platform)})';
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
    required super.tooltip,
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
    required super.tooltip,
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
    tooltip: 'Undo',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyZ),
    direction: _UndoDirection.undo,
  ),
  _UndoManagerShortcut(
    icon: Icons.redo,
    tooltip: 'Redo',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyZ, shift: true),
    direction: _UndoDirection.redo,
  ),
  _WrapShortcut(
    icon: Icons.format_bold,
    tooltip: 'Bold',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyB),
    marker: '**',
  ),
  _WrapShortcut(
    icon: Icons.format_italic,
    tooltip: 'Italic',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyI),
    marker: '*',
  ),
  _WrapShortcut(
    icon: Icons.strikethrough_s,
    tooltip: 'Strikethrough',
    marker: '~~',
  ),
  _WrapShortcut(
    icon: Icons.code,
    tooltip: 'Inline code',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyE),
    marker: '`',
  ),
  _LinePrefixShortcut(icon: Icons.title, tooltip: 'Heading 1', prefix: '# '),
  _LinePrefixShortcut(
    icon: Icons.text_fields,
    tooltip: 'Heading 2',
    prefix: '## ',
  ),
  _LinePrefixShortcut(
    icon: Icons.short_text,
    tooltip: 'Heading 3',
    prefix: '### ',
  ),
  _LinePrefixShortcut(icon: Icons.format_quote, tooltip: 'Quote', prefix: '> '),
  _LinePrefixShortcut(
    icon: Icons.format_list_bulleted,
    tooltip: 'Bullet list',
    prefix: '- ',
  ),
  _LinkLikeShortcut(
    icon: Icons.link,
    tooltip: 'Link',
    binding: EditorShortcutBinding(LogicalKeyboardKey.keyK),
    open: '[',
  ),
  _LinkLikeShortcut(icon: Icons.image, tooltip: 'Image', open: '!['),
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
    required super.tooltip,
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
    required super.tooltip,
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
    required super.tooltip,
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
