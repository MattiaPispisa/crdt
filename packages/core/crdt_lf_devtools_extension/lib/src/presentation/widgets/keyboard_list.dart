// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A list of rows of [defaultRowHeight] where the up and down keys move
/// the selection.
///
/// A tap in the list gives it the keyboard focus. A key move scrolls the
/// new row into view.
class KeyboardList extends StatefulWidget {
  const KeyboardList({
    required this.itemCount,
    required this.itemBuilder,
    required this.selectedIndex,
    required this.onSelect,
    this.canSelect,
    super.key,
  });

  final int itemCount;

  final IndexedWidgetBuilder itemBuilder;

  /// The index of the selected row; `null` when there is none.
  ///
  /// Called on a key press only.
  final int? Function() selectedIndex;

  /// Called with the row a key moves the selection to.
  final ValueChanged<int> onSelect;

  /// Whether the row at an index can be selected; every row when `null`.
  final bool Function(int index)? canSelect;

  @override
  State<KeyboardList> createState() => _KeyboardListState();
}

class _KeyboardListState extends State<KeyboardList> {
  final FocusNode _focus = FocusNode(debugLabel: 'KeyboardList');

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    final count = widget.itemCount;
    final canSelect = widget.canSelect ?? (_) => true;
    var i = widget.selectedIndex() ?? (step > 0 ? -1 : count);
    do {
      i += step;
    } while (i >= 0 && i < count && !canSelect(i));
    if (i >= 0 && i < count) {
      widget.onSelect(i);
      _reveal(i);
    }
    return KeyEventResult.handled;
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * defaultRowHeight;
    final bottom = top + defaultRowHeight;
    final viewport = position.viewportDimension;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + viewport) {
      _scroll.jumpTo(bottom - viewport);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: ListView.builder(
          controller: _scroll,
          itemCount: widget.itemCount,
          itemExtent: defaultRowHeight,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}
