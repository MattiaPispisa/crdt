import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';
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
  CRDTDocument? _document;
  CRDTUndoManager? _undo;
  AwarenessService? _awareness;
  WebSocketRelayClient? _sync;
  ValueNotifier<ConnectionStatus>? _status;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  CRDTDocumentPersistence? _persistence;
  bool _initialized = false;
  bool _restored = false;
  _ViewMode _mode = _ViewMode.split;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final profile = context.read<UserSettingsCubit>().state;
    unawaited(_restoreThenConnect(profile));
  }

  /// Brings back what the last session left on this device, then goes online.
  ///
  /// In that order on purpose: offline, or on a relay that has forgotten the
  /// room, the local copy is all there is. Connecting first would show an
  /// empty page for as long as the handshake takes.
  Future<void> _restoreThenConnect(UserSettingsState profile) async {
    // The identity of the last session, so this device stays one author. A
    // document given no peer id mints a new one, and the room's version vector
    // would gain an entry on every launch — carried inside every snapshot from
    // then on.
    final peerId = await _storedPeerId();

    // The document id IS the relay room key: every client of the room must
    // use the same one.
    final document = CRDTDocument(documentId: widget.roomId, peerId: peerId);
    final text = CRDTFugueTextHandler(document, kHandlerId);
    _document = document;
    _undo = CRDTUndoManager(document)..track(text);
    final awareness = AwarenessService(
      name: profile.displayName,
      color: profile.color,
    );
    _awareness = awareness;
    final sync = WebSocketRelayClient(
      url: roomUrl(kServerUrl, widget.roomId),
      document: document,
      author: document.peerId,
      plugins: [awareness.plugin],
    );
    _sync = sync;
    _status = ValueNotifier(sync.connectionStatusValue);
    _statusSubscription = sync.connectionStatus.listen(
      (status) => _status?.value = status,
    );

    try {
      _persistence = await CRDTDocumentPersistence.open(
        document,
        await CRDTHive.openStorageForDocument(document.documentId),
        onError: _reportPersistenceError,
      );
    } catch (error, stackTrace) {
      // A room with no local copy still works — it just starts empty and
      // fills up from the relay.
      _reportPersistenceError(error, stackTrace);
    }
    if (!mounted) {
      return;
    }
    setState(() => _restored = true);
    // Only now: the restored document is what the relay is caught up against,
    // so anything written offline goes out with the next welcome.
    sync.connect();
  }

  /// The id this device wrote under before, or a new one.
  ///
  /// A device that cannot read its storage still edits the room — under a new
  /// identity, which is what happened on every launch before this.
  Future<PeerId> _storedPeerId() async {
    try {
      final storage = await CRDTHive.openPeerIdStorageForDocument(
        widget.roomId,
      );
      return await storage.loadOrCreate();
    } catch (error, stackTrace) {
      _reportPersistenceError(error, stackTrace);
      return PeerId.generate();
    }
  }

  void _reportPersistenceError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'greyhound_markdown',
        context: ErrorDescription('storing room ${widget.roomId}'),
      ),
    );
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    // Flushes whatever is still waiting to be written.
    unawaited(_persistence?.dispose());
    // Disposes the awareness plugin too.
    _sync?.dispose();
    _awareness?.dispose();
    _status?.dispose();
    _undo?.dispose();
    _document?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final awareness = _awareness;
    final undo = _undo;
    final status = _status;
    if (!_restored ||
        document == null ||
        awareness == null ||
        undo == null ||
        status == null) {
      // Reading the local copy back. Showing the editor first would let
      // someone type into a document that is about to be replaced.
      return Scaffold(
        appBar: AppBar(title: Text('Room ${widget.roomId}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return CrdtProvider.value(
      value: document,
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            final editor = EditorPane(awareness: awareness, undo: undo);
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
            StatusBar(status: status, peers: awareness.peers),
            const AppFooter(),
          ],
        ),
      ),
    );
  }
}
