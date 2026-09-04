import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/src/services/room/room_session.dart';
import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/export_menu.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/room_builder.dart';
import 'package:greyhound_markdown_client/src/widgets/status_bar.dart';

/// The collaborative room. A segmented control switches between edit, split
/// (side by side, stacked on narrow screens) and view-only layouts.
///
/// The room itself — document, undo, awareness, sync — belongs to
/// [RoomBuilder]. This screen only draws it, and the only state it keeps is
/// which of the three layouts is showing.
class EditorScreen extends StatefulWidget {
  const EditorScreen({required this.roomId, super.key});

  final String roomId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _ViewMode { edit, split, view }

class _EditorScreenState extends State<EditorScreen> {
  _ViewMode _mode = _ViewMode.split;

  @override
  Widget build(BuildContext context) {
    return RoomBuilder(
      roomId: widget.roomId,
      // The frame of the page, so nothing jumps when the room arrives.
      loading: (context) => Scaffold(
        appBar: AppBar(title: Text('Room ${widget.roomId}')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      builder: _buildRoom,
    );
  }

  Widget _buildRoom(BuildContext context, RoomSession room) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${widget.roomId}'),
        actions: [
          IconButton(
            tooltip: 'Copy room id',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.roomId));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Room id copied')));
            },
          ),
          ExportMenu(fallbackName: 'greyhound-${widget.roomId}'),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<_ViewMode>(
              segments: const [
                ButtonSegment(
                  value: _ViewMode.edit,
                  icon: Icon(Icons.edit),
                  label: Text('Edit'),
                ),
                ButtonSegment(
                  value: _ViewMode.split,
                  icon: Icon(Icons.vertical_split),
                  label: Text('Split'),
                ),
                ButtonSegment(
                  value: _ViewMode.view,
                  icon: Icon(Icons.visibility),
                  label: Text('View'),
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
          final editor = EditorPane(
            awareness: room.awareness,
            undo: room.undo,
          );
          const preview = PreviewPane();
          switch (_mode) {
            case _ViewMode.edit:
              return editor;
            case _ViewMode.view:
              return preview;
            case _ViewMode.split:
              // Side by side when there is room, stacked otherwise.
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
