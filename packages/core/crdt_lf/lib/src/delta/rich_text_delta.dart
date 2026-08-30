import 'package:crdt_lf/src/delta/handler_update.dart';
import 'package:crdt_lf/src/delta/sequence_delta.dart';
import 'package:crdt_lf/src/handler/rich_text/mark.dart';

/// How a rich text handler's value moved: the characters, and the formatting.
///
/// The two halves are carried differently on purpose. [text] is a
/// [SequenceDelta], so a consumer pays the size of the edit rather than the
/// size of the document — that is the expensive half. [spans] is the whole
/// formatting of the document, because formatting is small next to text and
/// because a span cannot be moved by the text delta alone: a mark grows when
/// text is typed at its edge, so its end is not simply its old end shifted.
///
/// [spans] is `null` when the formatting did not move, which is the common
/// case while someone is typing in the middle of a paragraph.
final class RichTextDelta implements ComposableDelta<RichTextDelta> {
  /// Creates a delta moving the text by [text] and the formatting to [spans].
  const RichTextDelta({required this.text, this.spans});

  /// The delta that moves nothing.
  const RichTextDelta.empty()
      : text = const SequenceDelta<String>.empty(),
        spans = null;

  /// What happened to the characters, one element per rune.
  final SequenceDelta<String> text;

  /// The formatting of the whole document, or `null` when it did not move.
  final List<MarkSpan>? spans;

  @override
  bool get isEmpty => text.isEmpty && spans == null;

  @override
  RichTextDelta compose(RichTextDelta next) {
    return RichTextDelta(
      text: text.compose(next.text),
      // The later formatting is already the formatting of the whole document,
      // so it replaces this one rather than being merged into it.
      spans: next.spans ?? spans,
    );
  }

  /// The value [base] becomes once this delta is applied.
  RichTextValue apply(RichTextValue base) {
    return RichTextValue(
      text: text.applyToText(base.text),
      spans: spans ?? base.spans,
    );
  }

  @override
  String toString() => 'RichTextDelta($text, spans: $spans)';
}
