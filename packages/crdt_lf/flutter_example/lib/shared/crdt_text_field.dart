import 'package:flutter/material.dart';

/// An inline text field bound to a collaborative text value.
///
/// The parent passes the current [value] (read from a `CRDTFugueTextHandler`)
/// and an [onChanged] callback (which typically calls `handler.change(...)`).
///
/// Remote edits are adopted only while the field is **not** focused, so the
/// caret does not jump under the user while they are typing locally.
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
    // Adopt external (remote) edits only when the user is not typing here.
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
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
