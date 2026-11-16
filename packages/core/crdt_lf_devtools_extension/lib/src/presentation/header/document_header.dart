// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_color.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The document selector, the counters of the selected document and a
/// refresh button.
class DocumentHeader extends StatelessWidget {
  const DocumentHeader({required this.state, super.key});

  final DocumentsState state;

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  /// The selector text of [d]: its tracked id, and the first 8 characters
  /// of its document id and of its peer id.
  static String label(DocumentSummary d) =>
      '#${d.id} · ${_short(d.documentId)} · ${_short(d.peerId)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = state.selected;
    return AreaPaneHeader(
      roundedTopBorder: false,
      includeTopBorder: false,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            RoundedDropDownButton<int>(
              value: state.selectedId,
              style: theme.fixedFontStyle,
              onChanged: (id) {
                if (id != null) context.read<DocumentsCubit>().select(id);
              },
              items: [
                for (final d in state.documents)
                  DropdownMenuItem(
                    value: d.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: peerColor(d.peerId),
                        ),
                        const SizedBox(width: densePadding),
                        Text(label(d)),
                      ],
                    ),
                  ),
              ],
            ),
            if (selected != null) ..._labels(selected),
          ],
        ),
      ),
      actions: [
        DevToolsButton.iconOnly(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: () => context.read<DocumentsCubit>().refresh(),
        ),
      ],
    );
  }

  List<Widget> _labels(DocumentSummary d) => [
    for (final text in [
      '${d.changeCount} changes',
      '${d.handlerCount} handlers',
      '${d.frontiers.length} frontiers',
      'snapshot: ${d.snapshotId == null ? 'no' : 'yes'}',
      '${d.undoManagers} undo managers',
    ]) ...[const SizedBox(width: denseSpacing), RoundedLabel(labelText: text)],
  ];
}
