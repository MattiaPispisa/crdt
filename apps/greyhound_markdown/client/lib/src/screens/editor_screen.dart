import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/sync_client.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/status_bar.dart';

/// The collaborative room: owns the document and the sync/awareness
/// services for its lifetime, and lays out editor + preview side by side
/// (tabs on narrow screens).
class EditorScreen extends StatefulWidget {
  const EditorScreen({required this.roomId, super.key});

  final String roomId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CRDTDocument _document;
  late final AwarenessService _awareness;
  late final SyncClient _sync;
  bool _initialized = false;

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
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final editor = EditorPane(awareness: _awareness);
            const preview = PreviewPane();
            if (constraints.maxWidth < 720) {
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Write'),
                        Tab(text: 'Preview'),
                      ],
                    ),
                    Expanded(child: TabBarView(children: [editor, preview])),
                  ],
                ),
              );
            }
            return Row(
              children: [
                Expanded(child: editor),
                const VerticalDivider(width: 1),
                const Expanded(child: preview),
              ],
            );
          },
        ),
        bottomNavigationBar: StatusBar(
          status: _sync.status,
          peers: _awareness.peers,
        ),
      ),
    );
  }
}
