import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/widgets/markdown_shortcuts.dart';

/// A horizontally scrollable row of markdown formatting buttons.
///
/// Pure iteration over [kMarkdownShortcuts]: each button applies its shortcut
/// to the bound [controller] and hands focus back to the editor so typing can
/// continue. Mutating [controller] is what drives the CRDT edit — the text
/// binding listens to it.
class EditorToolbar extends StatelessWidget {
  /// Create an editor toolbar.
  const EditorToolbar({
    required this.controller,
    required this.focusNode,
    super.key,
  });

  /// The editor's text controller (owned by the CRDT text binding).
  final TextEditingController controller;

  /// The editor field's focus node, re-focused after a button tap.
  final FocusNode focusNode;

  void _apply(MarkdownShortcut shortcut) {
    controller.value = shortcut.apply(controller.value);
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final shortcut in kMarkdownShortcuts)
            IconButton(
              icon: Icon(shortcut.icon),
              tooltip: shortcut.tooltip,
              iconSize: 20,
              onPressed: () => _apply(shortcut),
            ),
        ],
      ),
    );
  }
}
