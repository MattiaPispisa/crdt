import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/persistence/document_cache.dart';
import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';
import 'package:greyhound_markdown_client/src/widgets/export_menu.dart';
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
  late final CRDTUndoManager _undo;
  late final AwarenessService _awareness;
  late final WebSocketRelayClient _sync;
  late final ValueNotifier<ConnectionStatus> _status;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  DocumentCache? _cache;
  bool _initialized = false;
  bool _restored = false;
  _ViewMode _mode = _ViewMode.split;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final profile = context.read<UserSettingsCubit>().state;
    // The document id IS the relay room key: every client of the room must
    // use the same one.
    _document = CRDTDocument(documentId: widget.roomId);
    final text = CRDTFugueTextHandler(_document, kHandlerId);
    _undo = CRDTUndoManager(_document)..track(text);
    _awareness = AwarenessService(
      name: profile.displayName,
      color: profile.color,
    );
    _sync = WebSocketRelayClient(
      url: roomUrl(kServerUrl, widget.roomId),
      document: _document,
      author: _document.peerId,
      plugins: [_awareness.plugin],
    );
    _status = ValueNotifier(_sync.connectionStatusValue);
    _statusSubscription = _sync.connectionStatus.listen(
      (status) => _status.value = status,
    );
    unawaited(_restoreThenConnect());
  }

  /// Brings back what the last session left on this device, then goes online.
  ///
  /// In that order on purpose: offline, or on a relay that has forgotten the
  /// room, the local copy is all there is. Connecting first would show an
  /// empty page for as long as the handshake takes.
  Future<void> _restoreThenConnect() async {
    try {
      _cache = await DocumentCache.open(_document, _sync);
    } catch (error, stackTrace) {
      // A room with no local cache still works — it just starts empty and
      // fills up from the relay.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'greyhound_markdown',
          context: ErrorDescription('restoring room ${widget.roomId}'),
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _restored = true);
    _sync.connect();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    // Flushes whatever is still waiting to be written.
    unawaited(_cache?.dispose());
    // Disposes the awareness plugin too.
    _sync.dispose();
    _awareness.dispose();
    _status.dispose();
    _undo.dispose();
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
        body: !_restored
            // Reading the local copy back. Showing the editor first would let
            // someone type into a document that is about to be replaced.
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final editor = EditorPane(awareness: _awareness, undo: _undo);
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
            StatusBar(status: _status, peers: _awareness.peers),
            const AppFooter(),
          ],
        ),
      ),
    );
  }
}
