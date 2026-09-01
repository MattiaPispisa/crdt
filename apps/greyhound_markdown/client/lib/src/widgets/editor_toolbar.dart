import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/widgets/markdown_shortcuts.dart';

/// A horizontally scrollable row of editor buttons.
///
/// Pure iteration over [kMarkdownShortcuts]: each button asks its shortcut
/// whether it can run, and on tap tells it to, then hands focus back to the
/// editor so typing can continue. Undo and redo are entries of that list like
/// any other — the toolbar does not know that they write to the document while
/// the rest rewrite the field.
///
/// It rebuilds on [CRDTUndoManager.changes], which is what greys undo and redo
/// out when their stack runs empty.
class EditorToolbar extends StatefulWidget {
  /// Create an editor toolbar.
  const EditorToolbar({
    required this.controller,
    required this.focusNode,
    required this.undo,
    super.key,
  });

  /// The editor's text controller (owned by the CRDT text binding).
  final TextEditingController controller;

  /// The editor field's focus node, re-focused after a button tap.
  final FocusNode focusNode;

  /// The room's undo history.
  final CRDTUndoManager undo;

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.undo.changes.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _run(MarkdownShortcut shortcut, EditorShortcutTarget target) {
    shortcut.run(target);
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final target = (controller: widget.controller, undo: widget.undo);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final shortcut in kMarkdownShortcuts)
            IconButton(
              icon: Icon(shortcut.icon),
              tooltip: shortcut.tooltipFor(platform),
              iconSize: 20,
              onPressed: shortcut.isEnabled(target)
                  ? () => _run(shortcut, target)
                  : null,
            ),
        ],
      ),
    );
  }
}
