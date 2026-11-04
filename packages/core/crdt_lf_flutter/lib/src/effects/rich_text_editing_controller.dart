// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Maps the attributes of a run to the style it is painted with.
typedef RichAttributeStyle = TextStyle Function(Map<String, Object?> map);

/// The default [RichAttributeStyle].
///
/// Reads `bold`, `italic`, `underline` and `strike` (booleans), `link`
/// (any value, painted blue and underlined), `color` (`'#rrggbb'`) and `size`
/// (a number).
TextStyle defaultRichAttributeStyle(Map<String, Object?> attributes) {
  final link = attributes['link'];
  final color = attributes['color'];
  final size = attributes['size'];
  final decorations = <TextDecoration>[
    if (attributes['underline'] == true || link != null)
      TextDecoration.underline,
    if (attributes['strike'] == true) TextDecoration.lineThrough,
  ];
  return TextStyle(
    fontWeight: attributes['bold'] == true ? FontWeight.bold : null,
    fontStyle: attributes['italic'] == true ? FontStyle.italic : null,
    decoration:
        decorations.isEmpty ? null : TextDecoration.combine(decorations),
    color: link != null
        ? const Color(0xFF1565C0)
        : color is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)
            ? Color(0xFF000000 | int.parse(color.substring(1), radix: 16))
            : null,
    fontSize: size is num ? size.toDouble() : null,
  );
}

/// A [TextEditingController] that paints its text from [RichTextSpan]s.
///
/// `CrdtRichTextFieldBuilder` creates and owns one. [text] is the plain
/// string, so selection and composing work as in a plain field. Formats go
/// through [format] and [toggle], which write to the handler.
class CrdtRichTextEditingController extends TextEditingController {
  /// Creates a controller that shows [spans].
  CrdtRichTextEditingController({
    List<RichTextSpan> spans = const [],
    this.styleOf = defaultRichAttributeStyle,
  })  : _spans = spans,
        _spansText = joinSpans(spans),
        super(text: joinSpans(spans));

  List<RichTextSpan> _spans;
  String _spansText;

  /// The style of each run.
  RichAttributeStyle styleOf;

  Map<String, Object?> _pending = const {};

  /// The field that owns the controller; formats and undo go through it.
  CrdtRichTextEditingDelegate? delegate;

  /// The committed spans, those the handler holds.
  List<RichTextSpan> get spans => _spans;

  /// The plain text of [spans].
  String get spansText => _spansText;

  /// Attributes of the text typed next at a collapsed caret.
  ///
  /// Empty when the caret has no style of its own.
  Map<String, Object?> get pendingAttributes => _pending;

  set pendingAttributes(Map<String, Object?> value) {
    if (mapEquals(_pending, value)) {
      return;
    }
    _pending = value;
    notifyListeners();
  }

  /// Sets [key] to [value] on the selection; `null` removes it.
  ///
  /// At a collapsed caret it styles the text typed next instead. A
  /// [MarkExpand] decides whether text typed at the edges of the range joins
  /// it. Does nothing while an IME composition is pending.
  void format(
    String key,
    Object? value, {
    MarkExpand expand = MarkExpand.after,
  }) =>
      delegate?.format(key, value, expand);

  /// The value of [key] shared by the whole selection, or at the caret.
  ///
  /// `null` when the selection mixes values, or the field has no selection.
  Object? attributeAtSelection(String key) =>
      delegate?.attributeAtSelection(key);

  /// Turns the boolean [key] on, or off when the selection already has it.
  void toggle(String key) {
    format(key, attributeAtSelection(key) == true ? null : true);
  }

  /// Whether [undo] would take back a step.
  bool get canUndo => delegate?.canUndo ?? false;

  /// Whether [redo] would restore a step.
  bool get canRedo => delegate?.canRedo ?? false;

  /// Takes back your last edit through the `CRDTUndoManager` of the field.
  ///
  /// Does nothing without a manager, or while an IME composition is pending.
  void undo() => delegate?.undo();

  /// Restores the edit [undo] took back.
  void redo() => delegate?.redo();

  /// Replaces the spans and the value with one notification.
  ///
  /// [newValue] must hold the plain text of [spans], except while a
  /// composition is pending.
  void setValueAndSpans(TextEditingValue newValue, List<RichTextSpan> spans) {
    _spans = spans;
    _spansText = joinSpans(spans);
    if (newValue == value) {
      notifyListeners();
    } else {
      value = newValue;
    }
  }

  /// The spans of the current [text]: [spans], plus the uncommitted run.
  ///
  /// The uncommitted run takes the attributes of the rune before it, with
  /// [pendingAttributes] on top.
  List<RichTextSpan> get displaySpans {
    final current = text;
    if (current == _spansText) {
      return _spans;
    }
    final delta = computeTextDelta(_spansText, current);
    if (delta == null) {
      return _spans;
    }
    final index = RuneOffsets.runeIndex(_spansText, delta.index);
    final deleted = delta.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(_spansText, delta.index + delta.deleted) -
            index;
    final attributes = {
      if (index > 0) ..._attributesAt(index - 1),
      ..._pending,
    }..removeWhere((_, value) => value == null);
    return RichTextDelta([
      RichTextRetain(index),
      RichTextDelete(deleted),
      RichTextInsert(delta.inserted, attributes),
    ]).apply(_spans);
  }

  Map<String, Object?> _attributesAt(int rune) {
    var start = 0;
    for (final span in _spans) {
      final end = start + RuneOffsets.length(span.text);
      if (rune < end) {
        return span.attributes;
      }
      start = end;
    }
    return const {};
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    var offset = 0;
    for (final span in displaySpans) {
      final runStyle = styleOf(span.attributes);
      final end = offset + span.text.length;
      if (composing.isValid &&
          composing.start < end &&
          composing.end > offset) {
        final from = composing.start > offset ? composing.start : offset;
        final to = composing.end < end ? composing.end : end;
        final underlined = runStyle.copyWith(
          decoration: TextDecoration.combine([
            if (runStyle.decoration != null) runStyle.decoration!,
            TextDecoration.underline,
          ]),
        );
        children.addAll([
          if (from > offset)
            TextSpan(
              text: span.text.substring(0, from - offset),
              style: runStyle,
            ),
          TextSpan(
            text: span.text.substring(from - offset, to - offset),
            style: underlined,
          ),
          if (to < end)
            TextSpan(text: span.text.substring(to - offset), style: runStyle),
        ]);
      } else {
        children.add(TextSpan(text: span.text, style: runStyle));
      }
      offset = end;
    }
    return TextSpan(style: style, children: children);
  }
}

/// What a [CrdtRichTextEditingController] asks of the field that owns it.
abstract interface class CrdtRichTextEditingDelegate {
  /// Formats the selection; see [CrdtRichTextEditingController.format].
  void format(String key, Object? value, MarkExpand expand);

  /// See [CrdtRichTextEditingController.attributeAtSelection].
  Object? attributeAtSelection(String key);

  /// See [CrdtRichTextEditingController.canUndo].
  bool get canUndo;

  /// See [CrdtRichTextEditingController.canRedo].
  bool get canRedo;

  /// See [CrdtRichTextEditingController.undo].
  void undo();

  /// See [CrdtRichTextEditingController.redo].
  void redo();
}

/// The plain text of [spans].
String joinSpans(List<RichTextSpan> spans) =>
    spans.length == 1 ? spans.first.text : spans.map((s) => s.text).join();

/// How many runes [spans] hold.
int runesOfSpans(List<RichTextSpan> spans) {
  var count = 0;
  for (final span in spans) {
    count += RuneOffsets.length(span.text);
  }
  return count;
}

/// Whether two span lists give every rune the same attributes and embed.
bool sameRuneAttributes(List<RichTextSpan> a, List<RichTextSpan> b) {
  var i = 0;
  var j = 0;
  var left = 0;
  var right = 0;
  while (i < a.length && j < b.length) {
    if (left == 0) {
      left = RuneOffsets.length(a[i].text);
    }
    if (right == 0) {
      right = RuneOffsets.length(b[j].text);
    }
    if (!mapEquals(a[i].attributes, b[j].attributes)) {
      return false;
    }
    if ((a[i].embed != null || b[j].embed != null) && a[i] != b[j]) {
      return false;
    }
    final step = left < right ? left : right;
    left -= step;
    right -= step;
    if (left == 0) {
      i++;
    }
    if (right == 0) {
      j++;
    }
  }
  return i == a.length && j == b.length;
}
