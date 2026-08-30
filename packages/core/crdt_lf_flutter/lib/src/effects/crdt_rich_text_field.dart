import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/_text_sync.dart';
import 'package:crdt_lf_flutter/src/effects/crdt_rich_text_controller.dart';
import 'package:flutter/widgets.dart';

/// {@template crdt_rich_text_field_builder}
/// Binds a [CrdtRichTextController] to the `CRDTRichTextHandler` registered
/// under [id]: text whose formatting lives **outside** the characters.
///
/// It is `CrdtTextFieldBuilder` with the formatting added, and the same
/// binding underneath — local edits pushed as the precise delta of each
/// gesture, IME composition respected, remote changes adopted with the caret
/// anchored to the identity of the element left of it, and a subtree that
/// never rebuilds. See that widget for the details of all four.
///
/// What this one adds is the formatting: the controller it hands to [builder]
/// paints the marks with [resolveMarkStyle], and carries
/// [CrdtRichTextController.applyMark], [CrdtRichTextController.removeMark] and
/// [CrdtRichTextController.toggleMark] for a toolbar to call.
///
/// Only **inline** marks can be painted in a text field. See
/// [CrdtRichTextController].
///
/// ## Example
/// ```dart
/// CrdtRichTextFieldBuilder(
///   id: 'body',
///   resolveMarkStyle: (type, value) => switch (type) {
///     'bold' => const TextStyle(fontWeight: FontWeight.bold),
///     'italic' => const TextStyle(fontStyle: FontStyle.italic),
///     _ => null,
///   },
///   builder: (context, controller) => Column(
///     children: [
///       TextButton(
///         onPressed: () => controller.toggleMark('bold', value: true),
///         child: const Text('Bold'),
///       ),
///       TextField(controller: controller, maxLines: null),
///     ],
///   ),
/// ),
/// ```
/// {@endtemplate}
class CrdtRichTextFieldBuilder extends StatefulWidget {
  /// Create a CrdtRichTextFieldBuilder.
  ///
  /// {@macro crdt_rich_text_field_builder}
  const CrdtRichTextFieldBuilder({
    required this.id,
    required this.resolveMarkStyle,
    required this.builder,
    this.onSelectionAnchorsChanged,
    super.key,
  });

  /// The id of the rich text handler to bind (as registered on the document).
  final String id;

  /// Turns a mark into the style that paints it.
  final MarkStyleResolver resolveMarkStyle;

  /// Called once with the [CrdtRichTextController] this widget owns.
  final Widget Function(
    BuildContext context,
    CrdtRichTextController controller,
  ) builder;

  /// Called whenever the stable anchors of the local selection change, ready
  /// to be published as ephemeral presence so other peers can draw this
  /// user's cursor with `CrdtTextCursorsOverlay`.
  ///
  /// Same contract as `CrdtTextFieldBuilder.onSelectionAnchorsChanged`.
  final void Function(FugueElementID? base, FugueElementID? extent)?
      onSelectionAnchorsChanged;

  @override
  State<CrdtRichTextFieldBuilder> createState() =>
      _CrdtRichTextFieldBuilderState();
}

class _CrdtRichTextFieldBuilderState extends State<CrdtRichTextFieldBuilder> {
  CrdtRichTextController? _controller;

  /// The handler currently bound, so the controller's toolbar calls reach it.
  CRDTRichTextHandler? _handler;

  /// The spans read while attaching, before the controller exists.
  List<MarkSpan> _seeded = const [];

  @override
  Widget build(BuildContext context) {
    return TextSyncBuilder<RichTextValue, RichTextDelta>(
      id: widget.id,
      adapterFor: _adapterFor,
      createController: _createController,
      onSeed: _onSeed,
      onDelta: _onDelta,
      onSelectionAnchorsChanged: widget.onSelectionAnchorsChanged,
      builder: (context, controller) =>
          widget.builder(context, controller as CrdtRichTextController),
    );
  }

  TextHandlerAdapter<RichTextValue, RichTextDelta> _adapterFor(
    CRDTDocument document,
    String id,
  ) {
    final handler = document.registeredHandlers[id];
    if (handler is! CRDTRichTextHandler) {
      throw FlutterError(
        'CrdtRichTextFieldBuilder expected a CRDTRichTextHandler registered '
        'under id "$id", but found ${handler ?? 'none'}.',
      );
    }
    _handler = handler;
    return _RichTextAdapter(handler);
  }

  TextEditingController _createController(String text) {
    return _controller = CrdtRichTextController(
      text: text,
      resolveMarkStyle: widget.resolveMarkStyle,
      onApplyMark: _applyMark,
    )..spans = _seeded;
  }

  /// A read of the whole value: the formatting comes with it.
  void _onSeed(RichTextValue value) {
    _seeded = value.spans;
    _controller?.spans = value.spans;
  }

  /// A delta carries the formatting only when it moved.
  void _onDelta(RichTextDelta delta) {
    final spans = delta.spans;
    if (spans == null) {
      return;
    }
    _seeded = spans;
    _controller?.spans = spans;
  }

  void _applyMark(
    int start,
    int end,
    String type,
    Object? value, {
    required bool expand,
  }) {
    final handler = _handler;
    if (handler == null) {
      return;
    }
    if (value == null) {
      handler.removeMark(start: start, end: end, type: type, expand: expand);
    } else {
      handler.addMark(
        start: start,
        end: end,
        type: type,
        value: value,
        expand: expand,
      );
    }
  }
}

/// Binds `CRDTRichTextHandler`: the text half of its delta drives the field,
/// and `length` is an `O(1)` rune count.
class _RichTextAdapter
    extends TextHandlerAdapter<RichTextValue, RichTextDelta> {
  _RichTextAdapter(this._handler);

  final CRDTRichTextHandler _handler;

  @override
  DeltaProvider<RichTextValue, RichTextDelta> get provider => _handler;

  @override
  String textOf(RichTextValue value) => value.text;

  @override
  SequenceDelta<String>? textDeltaOf(RichTextDelta delta) => delta.text;

  @override
  void insert(int index, String text) => _handler.insert(index, text);

  @override
  void delete(int index, int count) => _handler.delete(index, count);

  @override
  bool agreesWith(String text, int runes) => _handler.length == runes;

  /// Reads the characters without resolving the formatting, which the strict
  /// debug check does not look at.
  @override
  String get debugWholeText => _handler.text;

  @override
  FugueElementID? stablePositionAt(int runeIndex) =>
      _handler.stablePositionAt(runeIndex);

  @override
  int? indexOfStablePosition(FugueElementID position) =>
      _handler.indexOfStablePosition(position);
}
