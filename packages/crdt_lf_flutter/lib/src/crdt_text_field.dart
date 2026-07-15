import 'package:flutter/material.dart';

/// {@template crdt_text_field_builder}
/// A text field builder bound to a collaborative CRDT text value.
///
/// The parent passes the current [value] (typically read
/// from a `CRDTTextHandler` or `CRDTFugueTextHandler`) and an
/// [builder] callback (which expose the [TextEditingController]).
///
/// The controller is always kept in sync with [value] — including while the
/// field is focused. This is required for correctness.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   value: _value,
///   builder: (context, textEditingController) {
///     return TextField(
///       controller: textEditingController,
///       onChanged: setValue,
///     );
///   },
/// ),
/// ```
/// {@endtemplate}
class CrdtTextFieldBuilder extends StatefulWidget {
  /// Create a CrdtTextFieldBuilder.
  ///
  /// {@macro crdt_text_field_builder}
  const CrdtTextFieldBuilder({
    required this.value,
    required this.builder,
    super.key,
  });

  /// The current text value (source of truth lives in the CRDT handler).
  final String value;

  /// Called with the [TextEditingController] internally handled
  final Widget Function(
    BuildContext context,
    TextEditingController textEditingController,
  ) builder;

  @override
  State<CrdtTextFieldBuilder> createState() => _CrdtTextFieldBuilderState();
}

class _CrdtTextFieldBuilderState extends State<CrdtTextFieldBuilder> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(CrdtTextFieldBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always adopt the merged value so the next local edit is diffed against
    // the up-to-date text (otherwise a `change(...)` would fight concurrent
    // remote edits). After a local keystroke `value == _controller.text`, so
    // this is a no-op and the caret does not move; it only runs for genuine
    // remote updates, where the caret is kept best-effort.
    if (widget.value != _controller.text) {
      final offset = _controller.selection.baseOffset;
      final caret = offset < 0
          ? widget.value.length
          : offset.clamp(0, widget.value.length);
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: caret),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}
