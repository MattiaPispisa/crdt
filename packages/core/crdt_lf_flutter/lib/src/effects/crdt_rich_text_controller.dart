import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';

/// Turns one mark into the style that paints it, or `null` to paint nothing.
///
/// Called for every span of every type, so it should be cheap and pure. The
/// styles of overlapping marks are merged in span order.
typedef MarkStyleResolver = TextStyle? Function(String type, Object value);

/// A [TextEditingController] that paints the formatting a
/// `CRDTRichTextHandler` holds.
///
/// The characters carry no markup: the formatting arrives as [spans] and is
/// turned into a styled [TextSpan] tree in [buildTextSpan], the extension
/// point Flutter provides for exactly this. The field around it stays an
/// ordinary [EditableText], so typing, selection, IME and the remote-caret
/// overlay all keep working.
///
/// Only **inline** styling is possible this way — bold, italic, strikethrough,
/// inline code, a link. Formatting that needs its own paragraph layout, such
/// as list bullets or a quote bar, does not fit a plain text field.
///
/// `CrdtRichTextFieldBuilder` creates one and keeps [spans] up to date; it is
/// rarely built by hand.
class CrdtRichTextController extends TextEditingController {
  /// Creates a controller painting its marks with [resolveMarkStyle].
  CrdtRichTextController({
    required this.resolveMarkStyle,
    this.onApplyMark,
    super.text,
  });

  /// Turns a mark into the style that paints it.
  final MarkStyleResolver resolveMarkStyle;

  List<MarkSpan> _spans = const [];

  /// The formatting covering [text], in **rune** offsets.
  List<MarkSpan> get spans => _spans;

  set spans(List<MarkSpan> value) {
    if (identical(value, _spans)) {
      return;
    }
    _spans = value;
    // The text is unchanged, so a listener that mirrors it does nothing; the
    // field repaints with the new styles.
    notifyListeners();
  }

  /// Writes a mark over a range of runes into the document.
  ///
  /// Wired by `CrdtRichTextFieldBuilder`. Left out, the mark methods below do
  /// nothing — a controller built by hand has no document to write to.
  final void Function(
    int start,
    int end,
    String type,
    Object? value, {
    required bool expand,
  })? onApplyMark;

  /// The types marking the character the selection starts at.
  ///
  /// What a toolbar reads to show which buttons are on.
  Set<String> get activeMarks {
    final at = selection.isValid ? selection.start : text.length;
    final rune = RuneOffsets.runeIndex(text, at.clamp(0, text.length));
    return {
      for (final span in _spans)
        if (rune >= span.start && rune < span.end) span.type,
    };
  }

  /// The value of [type] on the character the selection starts at, or `null`
  /// when it carries none.
  Object? markValue(String type) {
    final at = selection.isValid ? selection.start : text.length;
    final rune = RuneOffsets.runeIndex(text, at.clamp(0, text.length));
    for (final span in _spans) {
      if (span.type == type && rune >= span.start && rune < span.end) {
        return span.value;
      }
    }
    return null;
  }

  /// Sets [type] to [value] over the current selection.
  ///
  /// Does nothing without a selection: a mark covers characters, and a caret
  /// covers none. Turn [expand] off for a link, so that text typed next to it
  /// is not dragged in.
  void applyMark(String type, {required Object value, bool expand = true}) {
    _selected(
      (start, end) =>
          onApplyMark?.call(start, end, type, value, expand: expand),
    );
  }

  /// Takes [type] off the current selection.
  ///
  /// [expand] must match what [applyMark] was given, or text typed at the
  /// edge takes the old value back.
  void removeMark(String type, {bool expand = true}) {
    _selected(
      (start, end) => onApplyMark?.call(start, end, type, null, expand: expand),
    );
  }

  /// Turns [type] on where the selection has none, and off where it has it.
  void toggleMark(String type, {required Object value, bool expand = true}) {
    if (activeMarks.contains(type)) {
      removeMark(type, expand: expand);
    } else {
      applyMark(type, value: value, expand: expand);
    }
  }

  void _selected(void Function(int start, int end) run) {
    final current = selection;
    if (!current.isValid || current.isCollapsed) {
      return;
    }
    run(
      RuneOffsets.runeIndex(text, current.start),
      RuneOffsets.runeIndex(text, current.end),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final content = value.text;
    if (_spans.isEmpty || content.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // The spans count runes; a TextSpan counts code units.
    final marks = <({int start, int end, TextStyle style})>[];
    for (final span in _spans) {
      final resolved = resolveMarkStyle(span.type, span.value);
      if (resolved == null) {
        continue;
      }
      final start = RuneOffsets.utf16Offset(content, span.start);
      final end = RuneOffsets.utf16Offset(content, span.end);
      if (end > start) {
        marks.add((start: start, end: end, style: resolved));
      }
    }
    if (marks.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // The composing region keeps the underline the base class gives it, or
    // IME feedback disappears while a character is being composed.
    final composing = withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : null;

    final cuts = <int>{0, content.length};
    for (final mark in marks) {
      cuts
        ..add(mark.start)
        ..add(mark.end);
    }
    if (composing != null) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final boundaries = cuts.where((c) => c >= 0 && c <= content.length).toList()
      ..sort();

    final children = <TextSpan>[];
    for (var i = 0; i < boundaries.length - 1; i += 1) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      if (end <= start) {
        continue;
      }

      var merged = const TextStyle();
      for (final mark in marks) {
        if (mark.start <= start && mark.end >= end) {
          merged = merged.merge(mark.style);
        }
      }
      if (composing != null &&
          composing.start <= start &&
          composing.end >= end) {
        merged = merged.merge(
          const TextStyle(decoration: TextDecoration.underline),
        );
      }

      children.add(
        TextSpan(
          text: content.substring(start, end),
          style: merged,
        ),
      );
    }

    return TextSpan(style: style, children: children);
  }
}
