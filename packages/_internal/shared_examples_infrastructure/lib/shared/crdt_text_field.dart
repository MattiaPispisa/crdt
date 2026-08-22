import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared/example_sync_session.dart';
import 'package:shared_examples_infrastructure/shared/text_cursor_presence.dart';

/// An inline collaborative text field bound to a [CRDTFugueTextHandler].
///
/// The live field wraps [CrdtTextFieldBuilder]: local edits are pushed as
/// precise per-gesture deltas (no full-text diff), IME composition is
/// respected and the caret stays anchored across remote edits through stable
/// positions. If the pane's session exposes a [TextCursorPresence], the
/// local selection is published on it and the remote collaborators' cursors
/// are drawn over the field with [CrdtTextCursorsOverlay].
///
/// While time traveling ([enabled] is false, [handler] is the time-travel
/// view handler) — or while [handler] is not created yet — the field is a
/// read-only view of the handler value (the pane rebuilds it as the history
/// cursor moves).
class CrdtTextField extends StatelessWidget {
  /// Creates a collaborative text field over [handler].
  const CrdtTextField({
    super.key,
    required this.handler,
    this.enabled = true,
    this.hintText,
    this.style,
    this.maxLines = 1,
  });

  /// The text handler backing the field: the live handler, or the
  /// time-travel view handler (same id) while time traveling.
  final CRDTFugueTextHandler? handler;

  /// Whether the field can be edited (false while time traveling).
  final bool enabled;

  /// Optional hint shown when empty.
  final String? hintText;

  /// Optional text style.
  final TextStyle? style;

  /// Maximum number of lines (null for unbounded).
  final int? maxLines;

  InputDecoration get _decoration => InputDecoration(
    hintText: hintText,
    isDense: true,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final handler = this.handler;
    if (handler == null || !enabled) {
      return _StaticTextField(
        value: handler?.value ?? '',
        decoration: _decoration,
        style: style,
        maxLines: maxLines,
      );
    }

    final presence = context.read<ExampleSyncSession?>()?.textPresence;
    return CrdtTextFieldBuilder(
      id: handler.id,
      onSelectionAnchorsChanged:
          presence == null
              ? null
              : (base, extent) => presence.publish(handler.id, base, extent),
      builder: (context, controller) {
        final field = TextField(
          controller: controller,
          maxLines: maxLines,
          style: style,
          decoration: _decoration,
        );
        if (presence == null) {
          return field;
        }
        return ValueListenableBuilder<List<CrdtTextCursor>>(
          valueListenable: presence.cursorsOf(handler.id),
          builder:
              (context, cursors, child) => CrdtTextCursorsOverlay(
                id: handler.id,
                cursors: cursors,
                child: child!,
              ),
          child: field,
        );
      },
    );
  }
}

/// A disabled [TextField] kept in sync with an externally-changing [value]
/// (the time-travel view as the history cursor moves).
class _StaticTextField extends StatefulWidget {
  const _StaticTextField({
    required this.value,
    required this.decoration,
    required this.style,
    required this.maxLines,
  });

  final String value;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<_StaticTextField> createState() => _StaticTextFieldState();
}

class _StaticTextFieldState extends State<_StaticTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_StaticTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: false,
      maxLines: widget.maxLines,
      style: widget.style,
      decoration: widget.decoration,
    );
  }
}
