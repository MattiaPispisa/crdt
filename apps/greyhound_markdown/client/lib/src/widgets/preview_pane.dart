import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/app_markdown.dart';

/// How long typing has to pause before the preview re-renders.
///
/// Short enough to feel live, long enough that a burst of keystrokes costs one
/// render instead of one per key.
const Duration kPreviewDebounce = Duration(milliseconds: 150);

/// Rendered markdown preview.
///
/// When the document is still empty the [kPlaceholderMarkdown] welcome text is
/// rendered instead — purely visual, never written into the shared document.
///
/// Reading the text out of the handler and parsing it are both O(document), so
/// doing them per keystroke drops frames on a long document. This pane
/// therefore listens to the cheap per-handler revision and only reads and
/// renders once typing pauses for [kPreviewDebounce].
class PreviewPane extends StatelessWidget {
  /// Creates the preview pane.
  const PreviewPane({super.key});

  @override
  Widget build(BuildContext context) {
    return CrdtHandlerBuilder<CRDTFugueTextHandler>(
      id: kHandlerId,
      builder: (context, handler) => _DebouncedMarkdown(
        // A non-listening read: the rebuild already comes from
        // CrdtHandlerBuilder, this only tells the two apart from a rebuild
        // caused by an ancestor.
        revision: context.crdtDocument.revisionForHandler(kHandlerId),
        readText: () => handler.value,
      ),
    );
  }
}

/// Renders the markdown returned by [readText], refreshed at most once per
/// [kPreviewDebounce] and only when [revision] moves.
class _DebouncedMarkdown extends StatefulWidget {
  const _DebouncedMarkdown({
    required this.revision,
    required this.readText,
  });

  /// The handler revision the current [readText] belongs to.
  final int revision;

  /// Reads the current document text. Called on the trailing edge only.
  final String Function() readText;

  @override
  State<_DebouncedMarkdown> createState() => _DebouncedMarkdownState();
}

class _DebouncedMarkdownState extends State<_DebouncedMarkdown> {
  late String _text;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The first frame shows the document at once; only later edits wait.
    _text = widget.readText();
  }

  @override
  void didUpdateWidget(_DebouncedMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision == oldWidget.revision) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(kPreviewDebounce, () {
      // Read now rather than when the timer was armed: `widget` is the latest
      // one, so this picks up every edit made during the pause.
      setState(() => _text = widget.readText());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMarkdown(
      data: _text.isEmpty ? kPlaceholderMarkdown : _text,
    );
  }
}
