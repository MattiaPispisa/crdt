import 'package:flutter/material.dart';

/// An inline text field bound to a collaborative text value.
///
/// The parent passes the current [value] (read from a `CRDTFugueTextHandler`)
/// and an [onChanged] callback (which typically calls `handler.change(...)`).
///
/// The controller is always kept in sync with [value] — including while the
/// field is focused. This is required for correctness: `onChanged` reports the
/// full new text and the parent turns it into a `change(...)` (a diff against
/// the handler's current value). If the controller lagged behind a concurrent
/// remote edit, that diff would compute against a stale base and silently undo
/// the remote edit. The caret offset is preserved on a best-effort basis (it
/// may shift when a remote edit lands before it).
class CrdtTextField extends StatefulWidget {
  /// Creates a collaborative text field.
  const CrdtTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hintText,
    this.style,
    this.maxLines = 1,
  });

  /// The current text value (source of truth lives in the CRDT handler).
  final String value;

  /// Called on every local edit with the full updated text.
  final ValueChanged<String> onChanged;

  /// Whether the field can be edited (false while time traveling).
  final bool enabled;

  /// Optional hint shown when empty.
  final String? hintText;

  /// Optional text style.
  final TextStyle? style;

  /// Maximum number of lines (null for unbounded).
  final int? maxLines;

  @override
  State<CrdtTextField> createState() => _CrdtTextFieldState();
}

class _CrdtTextFieldState extends State<CrdtTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(CrdtTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always adopt the merged value so the next local edit is diffed against
    // the up-to-date text (otherwise a `change(...)` would fight concurrent
    // remote edits). After a local keystroke `value == _controller.text`, so
    // this is a no-op and the caret does not move; it only runs for genuine
    // remote updates, where the caret is kept best-effort.
    if (widget.value != _controller.text) {
      final offset = _controller.selection.baseOffset;
      final caret =
          offset < 0
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      style: widget.style,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
