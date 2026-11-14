// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// One entry of a [Select]: a [value] and the [label] that shows it.
class SelectOption<T> {
  /// Creates an entry that shows [value] as [label].
  const SelectOption({required this.value, required this.label});

  /// The value picked with this entry.
  final T value;

  /// The text of this entry, in the field and in the menu.
  final String label;
}

/// A field that shows the picked option and opens a menu of [options] below
/// it, as wide as the field.
class Select<T> extends StatelessWidget {
  /// Creates a field that shows [value] among [options].
  ///
  /// [value] must be the value of one of the [options].
  const Select({
    required this.value,
    required this.options,
    required this.onChanged,
    this.tooltip,
    super.key,
  });

  /// The picked value.
  final T value;

  /// The entries of the menu, in order.
  final List<SelectOption<T>> options;

  /// Called with the value of the entry the user picks.
  final ValueChanged<T> onChanged;

  /// The text shown when the pointer rests on the field; `null` for none.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere((option) => option.value == value);
    return LayoutBuilder(
      builder: (context, constraints) => PopupMenuButton<T>(
        initialValue: value,
        // An empty tooltip, not `null`: `null` shows "Show menu".
        tooltip: tooltip ?? '',
        position: PopupMenuPosition.under,
        constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem(value: option.value, child: Text(option.label)),
        ],
        onSelected: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(selected.label)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}
