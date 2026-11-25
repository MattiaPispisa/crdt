// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

/// A padded table of one labelled value per row.
class FieldTable extends StatelessWidget {
  const FieldTable(this.fields, {super.key});

  /// A table of texts in the fixed font.
  FieldTable.texts(List<(String, String)> fields, {super.key})
    : fields = [for (final (label, text) in fields) (label, _Fixed(text))];

  final List<(String, Widget)> fields;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).subtleTextStyle;
    return Padding(
      padding: const EdgeInsets.all(densePadding),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (final (label, value) in fields)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: defaultSpacing),
                  child: Text(label, style: subtle),
                ),
                value,
              ],
            ),
        ],
      ),
    );
  }
}

class _Fixed extends StatelessWidget {
  const _Fixed(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).fixedFontStyle);
}
