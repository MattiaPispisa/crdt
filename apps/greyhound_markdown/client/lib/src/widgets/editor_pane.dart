import 'dart:math' as math;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_toolbar.dart';
import 'package:greyhound_markdown_client/src/widgets/line_number_gutter.dart';
import 'package:greyhound_markdown_client/src/widgets/markdown_shortcuts.dart';

/// Padding between the editor text and the edges of its pane.
const double kEditorPadding = 16;

/// The style of the editor text, and of the line numbers next to it.
const TextStyle kEditorTextStyle = TextStyle(
  fontFamily: kMonospaceFontFamily,
  fontSize: 14,
);

/// The collaborative markdown source editor: a toolbar above a [TextField]
/// bound to the fugue text handler, with remote carets painted on top. The
/// toolbar actions that declare a key chord — undo and redo included — are also
/// reachable from the keyboard while focus is inside the pane.
///
/// Two local view options come from [UserSettingsCubit]: an optional
/// line-number gutter, and word wrap. They are read inside
/// [CrdtTextFieldBuilder.builder] rather than above the pane, so flipping one
/// never rebuilds the CRDT binding.
///
/// The cursors listenable sits inside [CrdtTextFieldBuilder.builder] so that
/// presence repaints never rebuild the text field itself.
class EditorPane extends StatefulWidget {
  const EditorPane({required this.awareness, required this.undo, super.key});

  final AwarenessService awareness;

  /// The room's undo history, owned by the screen so it outlives the layout
  /// switches that take this pane out of the tree.
  final CRDTUndoManager undo;

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
      builder: (context, controller) => CallbackShortcuts(
        // Sits below the app-wide DefaultTextEditingShortcuts and above the
        // field, so the chords win over the browser and over text editing
        // defaults while focus is anywhere in the pane. That is what sends ⌘Z
        // to the document's history rather than the field's own.
        bindings: markdownShortcutBindings(
          (controller: controller, undo: widget.undo),
          Theme.of(context).platform,
        ),
        child: Column(
          children: [
            EditorToolbar(
              controller: controller,
              focusNode: _focusNode,
              undo: widget.undo,
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<Map<String, PeerState>>(
                valueListenable: widget.awareness.peers,
                builder: (context, peers, child) => CrdtTextCursorsOverlay(
                  id: kHandlerId,
                  cursors: _toCursors(peers),
                  child: child!,
                ),
                child: EditorSurface(
                  controller: controller,
                  focusNode: _focusNode,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The two view options the editor reads from the user's settings.
typedef EditorOptions = ({bool lineNumbers, bool wordWrap});

/// The editing surface: the optional line-number gutter, and the text field
/// inside the viewport that gives it word wrap or sideways scrolling.
///
/// Sits below [CrdtTextCursorsOverlay] on purpose. The overlay finds the
/// field by walking its own render subtree and places carets with
/// `getTransformTo`, so the gutter and the horizontal viewport in between are
/// absorbed by that transform — and the overlay still clips carets to the
/// visible pane rather than to the (possibly much wider) content.
class EditorSurface extends StatefulWidget {
  /// Creates the editing surface.
  const EditorSurface({
    required this.controller,
    required this.focusNode,
    super.key,
  });

  /// The controller owned by the CRDT text binding.
  final TextEditingController controller;

  /// The field's focus node, shared with the toolbar.
  final FocusNode focusNode;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface> {
  /// The field's own vertical scroll. Passed in explicitly because the gutter
  /// needs it as a repaint signal — there is no other public one.
  final ScrollController _verticalScroll = ScrollController();

  /// The sideways scroll used when word wrap is off.
  final ScrollController _horizontalScroll = ScrollController();

  /// Marks the field's subtree, so the gutter can find its [RenderEditable].
  final GlobalKey _fieldKey = GlobalKey();

  bool _followScheduled = false;

  bool get _wordWrap => context.read<UserSettingsCubit>().state.wordWrap;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted || _followScheduled || _wordWrap) {
      return;
    }
    // After the frame: the just-typed character has to be part of the content
    // before its width — and the scroll extent — mean anything.
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      _followCaret();
    });
  }

  /// Brings the caret back into view after an edit pushed it past the edge.
  ///
  /// With word wrap off the field is laid out at the width of its longest
  /// line, so it never scrolls itself: the caret is always "visible" to it and
  /// only this outer viewport can follow.
  void _followCaret() {
    if (!mounted ||
        _wordWrap ||
        !widget.focusNode.hasFocus ||
        !_horizontalScroll.hasClients) {
      return;
    }
    final editable = _findEditable();
    final content = _fieldKey.currentContext?.findRenderObject();
    if (editable == null || !editable.attached || content is! RenderBox) {
      return;
    }
    final selection = widget.controller.selection;
    if (!selection.isValid) {
      return;
    }
    final caret = editable.getLocalRectForCaret(
      TextPosition(
        offset: selection.extentOffset.clamp(0, editable.plainText.length),
      ),
    );
    final x = MatrixUtils.transformPoint(
      editable.getTransformTo(content),
      caret.topLeft,
    ).dx;

    final position = _horizontalScroll.position;
    const margin = 24.0;
    final double? target;
    if (x < position.pixels + margin) {
      target = x - margin;
    } else if (x > position.pixels + position.viewportDimension - margin) {
      target = x - position.viewportDimension + margin;
    } else {
      target = null;
    }
    if (target == null) {
      return;
    }
    _horizontalScroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  RenderEditable? _findEditable() {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    _fieldKey.currentContext?.findRenderObject()?.visitChildren(visit);
    return found;
  }

  /// How wide the field may be laid out.
  ///
  /// Wrapping: exactly the viewport. Not wrapping: at least the viewport, and
  /// otherwise whatever the [IntrinsicWidth] below asks the field for.
  ///
  /// The field is the one that measures itself. Measuring the text here with
  /// a [TextPainter] of our own reads short — its longest line came out 84
  /// pixels narrower than what `RenderEditable` said it needed — and a field
  /// laid out even slightly too narrow wraps anyway.
  BoxConstraints _fieldConstraints(double viewport, {required bool wrap}) =>
      wrap
      ? BoxConstraints.tightFor(width: viewport)
      : BoxConstraints(minWidth: viewport);

  @override
  Widget build(BuildContext context) {
    return BlocSelector<UserSettingsCubit, UserSettingsState, EditorOptions>(
      selector: (settings) => (
        lineNumbers: settings.showLineNumbers,
        wordWrap: settings.wordWrap,
      ),
      builder: (context, options) {
        final numberStyle = kEditorTextStyle.copyWith(
          color: Theme.of(context).colorScheme.outline,
        );
        return LayoutBuilder(
          builder: (context, constraints) =>
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final lineCount = '\n'.allMatches(value.text).length + 1;
                  final gutterWidth = options.lineNumbers
                      ? lineNumberGutterWidth(lineCount, numberStyle)
                      : 0.0;
                  final viewport = math.max(
                    0.0,
                    constraints.maxWidth - gutterWidth,
                  );
                  return Row(
                    // The gutter is a CustomPaint with no child: under the
                    // default centered alignment it would size itself to zero
                    // height and paint nothing.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (options.lineNumbers)
                        LineNumberGutter(
                          controller: widget.controller,
                          scrollController: _verticalScroll,
                          fieldKey: _fieldKey,
                          width: gutterWidth,
                          style: numberStyle,
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              // Without a bar a long line just runs off the
                              // edge: a mouse wheel scrolls the field
                              // vertically, so there would be no visible way
                              // to reach the rest of the line.
                              child: Scrollbar(
                                controller: _horizontalScroll,
                                thumbVisibility: !options.wordWrap,
                                child: SingleChildScrollView(
                                  controller: _horizontalScroll,
                                  scrollDirection: Axis.horizontal,
                                  // Always in the tree: flipping word wrap
                                  // must change two numbers, not re-parent
                                  // the field. Re-parenting would throw away
                                  // its editing state and the render object
                                  // the cursors overlay holds on to.
                                  physics: options.wordWrap
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                                  child: ConstrainedBox(
                                    constraints: _fieldConstraints(
                                      viewport,
                                      wrap: options.wordWrap,
                                    ),
                                    // A no-op while wrapping (the width above
                                    // is tight); the field's own measurement
                                    // when it is not.
                                    child: IntrinsicWidth(child: _field),
                                  ),
                                ),
                              ),
                            ),
                            // The welcome document as a scrollable placeholder
                            // — a plain hint would overflow the pane (hints
                            // don't scroll). Shown only while the document is
                            // empty, and beside the gutter rather than over
                            // it. A tap focuses the editor.
                            if (value.text.isEmpty)
                              Positioned.fill(
                                child: _EditorPlaceholder(
                                  focusNode: widget.focusNode,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
        );
      },
    );
  }

  /// The field itself, built once: every rebuild above hands back the same
  /// instance, so the element and its render objects are only relaid out.
  late final Widget _field = KeyedSubtree(
    key: _fieldKey,
    child: TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      scrollController: _verticalScroll,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: kEditorTextStyle,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(kEditorPadding),
      ),
    ),
  );
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
        padding: const EdgeInsets.all(kEditorPadding),
        child: Text(
          kPlaceholderMarkdown,
          style: kEditorTextStyle.copyWith(
            color: Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }
}
