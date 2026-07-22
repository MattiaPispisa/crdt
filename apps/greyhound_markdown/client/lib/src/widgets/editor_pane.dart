import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_toolbar.dart';

/// The collaborative markdown source editor: a formatting toolbar above a
/// [TextField] bound to the fugue text handler, with remote carets painted on
/// top.
///
/// The cursors listenable sits inside [CrdtTextFieldBuilder.builder] so that
/// presence repaints never rebuild the text field itself.
class EditorPane extends StatefulWidget {
  const EditorPane({required this.awareness, super.key});

  final AwarenessService awareness;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
      onSelectionAnchorsChanged: widget.awareness.setLocalCursor,
      builder: (context, controller) => Column(
        children: [
          EditorToolbar(controller: controller, focusNode: _focusNode),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ValueListenableBuilder<Map<String, PeerState>>(
                    valueListenable: widget.awareness.peers,
                    builder: (context, peers, child) => CrdtTextCursorsOverlay(
                      id: kHandlerId,
                      cursors: _toCursors(peers),
                      child: child!,
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: kMonospaceFontFamily,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ),
                // The welcome document as a scrollable placeholder — a plain
                // hint would overflow the pane (hints don't scroll). Shown only
                // while the document is empty; a tap focuses the editor.
                Positioned.fill(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? _EditorPlaceholder(focusNode: _focusNode)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty-editor placeholder: the raw welcome markdown, scrollable and
/// clipped to the pane (a `TextField` hint would run off-screen). Tapping it
/// hands focus to the editor so the user can start typing.
class _EditorPlaceholder extends StatelessWidget {
  const _EditorPlaceholder({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          kPlaceholderMarkdown,
          style: TextStyle(
            fontFamily: kMonospaceFontFamily,
            fontSize: 14,
            color: Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }
}
