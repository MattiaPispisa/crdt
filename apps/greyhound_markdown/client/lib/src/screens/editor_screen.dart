import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/sync_client.dart';
import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/status_bar.dart';

/// The collaborative room: owns the document and the sync/awareness
/// services for its lifetime. A segmented control switches between edit,
/// split (side by side, stacked on narrow screens) and view-only layouts.
class EditorScreen extends StatefulWidget {
  const EditorScreen({required this.roomId, super.key});

  final String roomId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _ViewMode { edit, split, view }

class _EditorScreenState extends State<EditorScreen> {
  late final CRDTDocument _document;
  late final AwarenessService _awareness;
  late final SyncClient _sync;
  bool _initialized = false;
  _ViewMode _mode = _ViewMode.split;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final profile =
        ModalRoute.of(context)?.settings.arguments as HomeScreenArguments?;
    _document = CRDTDocument();
    CRDTFugueTextHandler(_document, kHandlerId);
    _awareness = AwarenessService(
      name: profile?.name ?? 'anonymous',
      color: profile?.color ?? Colors.blueGrey,
    );
    _sync = SyncClient(
      roomId: widget.roomId,
      document: _document,
      awareness: _awareness,
    )..connect();
  }

  @override
  void dispose() {
    _sync.dispose();
    _awareness.dispose();
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CrdtProvider.value(
      value: _document,
      child: Scaffold(
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
            final editor = EditorPane(awareness: _awareness);
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
            StatusBar(status: _sync.status, peers: _awareness.peers),
            const AppFooter(),
          ],
        ),
      ),
    );
  }
}
