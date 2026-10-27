// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/routing/app_navigation.dart';
import 'package:greyhound_markdown_client/src/services/room/room_session.dart';
import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/export_menu.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/status_bar.dart';

/// The collaborative room. A segmented control switches between edit, split
/// (side by side, stacked on narrow screens) and view-only layouts.
///
/// The room itself — document, undo, awareness, sync — belongs to
/// `RoomShell`, which holds it for every page of the room. This screen reads
/// it from the tree and only draws it, and the only state it keeps is which of
/// the three layouts is showing.
class EditorScreen extends StatefulWidget {
  /// Creates the editor of the room named by [roomId].
  const EditorScreen({required this.roomId, super.key});

  /// The room to draw. It is the document id and the relay room key.
  final String roomId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _ViewMode { edit, split, view }

class _EditorScreenState extends State<EditorScreen> {
  _ViewMode _mode = _ViewMode.split;

  @override
  Widget build(BuildContext context) {
    final room = context.read<RoomSession>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.roomTitle(widget.roomId)),
        actions: [
          IconButton(
            tooltip: context.l10n.copyRoomId,
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.roomId));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.roomIdCopied)),
              );
            },
          ),
          IconButton(
            tooltip: context.l10n.historyTitle,
            icon: const Icon(Icons.history),
            onPressed: () => context.goHistory(widget.roomId),
          ),
          ExportMenu(fallbackName: 'greyhound-${widget.roomId}'),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<_ViewMode>(
              segments: [
                ButtonSegment(
                  value: _ViewMode.edit,
                  icon: const Icon(Icons.edit),
                  label: Text(context.l10n.viewModeEdit),
                ),
                ButtonSegment(
                  value: _ViewMode.split,
                  icon: const Icon(Icons.vertical_split),
                  label: Text(context.l10n.viewModeSplit),
                ),
                ButtonSegment(
                  value: _ViewMode.view,
                  icon: const Icon(Icons.visibility),
                  label: Text(context.l10n.viewModeView),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.single),
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final editor = EditorPane(awareness: room.awareness, undo: room.undo);
          const preview = PreviewPane();
          switch (_mode) {
            case _ViewMode.edit:
              return editor;
            case _ViewMode.view:
              return preview;
            case _ViewMode.split:
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [
                    Expanded(child: editor),
                    const Divider(height: 1),
                    const Expanded(child: preview),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: editor),
                  const VerticalDivider(width: 1),
                  const Expanded(child: preview),
                ],
              );
          }
        },
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBar(status: room.status, peers: room.awareness.peers),
          const AppFooter(),
        ],
      ),
    );
  }
}
