import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';

/// The collaborative markdown source editor: a [TextField] bound to the
/// fugue text handler, with remote carets painted on top.
///
/// The cursors listenable sits inside [CrdtTextFieldBuilder.builder] so that
/// presence repaints never rebuild the text field itself.
class EditorPane extends StatelessWidget {
  const EditorPane({required this.awareness, super.key});

  final AwarenessService awareness;

  List<CrdtTextCursor> _toCursors(Map<String, PeerState> peers) => [
    for (final entry in peers.entries)
      if (entry.value.base != null)
        CrdtTextCursor(
          id: entry.key,
          label: entry.value.name,
          color: entry.value.color,
          base: entry.value.base!,
          extent: entry.value.extent,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    return CrdtTextFieldBuilder(
      id: kHandlerId,
      onSelectionAnchorsChanged: awareness.setLocalCursor,
      builder: (context, controller) =>
          ValueListenableBuilder<Map<String, PeerState>>(
            valueListenable: awareness.peers,
            builder: (context, peers, child) => CrdtTextCursorsOverlay(
              id: kHandlerId,
              cursors: _toCursors(peers),
              child: child!,
            ),
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
                hintText: '# Start writing markdown together…',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
    );
  }
}
