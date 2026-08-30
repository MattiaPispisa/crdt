import 'dart:collection';
import 'dart:typed_data';

import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/operation/id.dart';

/// Which side of a character a [MarkAnchor] sits on.
///
/// The side decides what happens to text typed at the boundary, so it is how a
/// mark that grows is told apart from one that does not. See [MarkAnchor].
enum MarkSide {
  /// The boundary sits immediately before the character.
  before,

  /// The boundary sits immediately after the character.
  after,
}

/// One end of a mark, tied to the **identity** of a character instead of to a
/// position.
///
/// The character keeps its identity while text around it is inserted and
/// deleted, so the boundary stays where the author put it. An anchor on a
/// character that was deleted resolves to where that character used to be, so
/// re-typing in that spot brings the mark back.
///
/// ## The side is what makes a mark grow
///
/// Take `a b c d e` with a mark over `c d`, and a character typed between `b`
/// and `c`:
///
/// - `after(b) .. before(e)` — the new character is after `b` and before `e`,
///   so it is **inside**. The mark grows at both edges. This is bold, italic
///   and strikethrough.
/// - `before(c) .. after(d)` — the new character sits before `c`, so it is
///   **outside**. The mark keeps its size. This is a link: typing next to one
///   must not drag it along.
///
/// One shape covers both, chosen per mark type.
class MarkAnchor {
  /// Creates an anchor on [side] of [id].
  const MarkAnchor(this.id, this.side);

  /// The boundary before the first character, wherever the text starts.
  factory MarkAnchor.documentStart() =>
      MarkAnchor(FugueElementID.nullID(), MarkSide.before);

  /// The boundary after the last character, wherever the text ends.
  factory MarkAnchor.documentEnd() =>
      MarkAnchor(FugueElementID.nullID(), MarkSide.after);

  /// Decodes an anchor from [bytes] starting at [offset].
  ///
  /// Layout: `side: u8`, then [FugueElementID] bytes.
  static MarkAnchorReadResult readFromBytes(
    Uint8List bytes, {
    int offset = 0,
  }) {
    if (offset >= bytes.length) {
      throw const FormatException('Truncated MarkAnchor');
    }
    final raw = bytes[offset];
    if (raw > MarkSide.values.length - 1) {
      throw FormatException('Invalid MarkSide: $raw');
    }
    final idRec = FugueElementID.readFromBytes(bytes, offset: offset + 1);
    return MarkAnchorReadResult(
      MarkAnchor(idRec.value, MarkSide.values[raw]),
      idRec.nextOffset,
    );
  }

  /// The character the boundary hangs off, or a null id for a document edge.
  final FugueElementID id;

  /// Which side of [id] the boundary sits on.
  final MarkSide side;

  /// Whether this anchor is the start of the text rather than a character.
  bool get isDocumentStart => id.isNull && side == MarkSide.before;

  /// Whether this anchor is the end of the text rather than a character.
  bool get isDocumentEnd => id.isNull && side == MarkSide.after;

  /// Encodes the anchor. See [readFromBytes] for the layout.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false)
      ..addByte(side.index)
      ..add(id.toBytes());
    return out.toBytes();
  }

  @override
  bool operator ==(Object other) =>
      other is MarkAnchor && other.id == id && other.side == side;

  @override
  int get hashCode => Object.hash(id, side);

  @override
  String toString() => '${side.name}($id)';
}

/// Result of decoding a [MarkAnchor] from a byte buffer.
class MarkAnchorReadResult {
  /// Creates a result holding [value] and [nextOffset].
  const MarkAnchorReadResult(this.value, this.nextOffset);

  /// The decoded anchor.
  final MarkAnchor value;

  /// The offset immediately after the decoded bytes.
  final int nextOffset;
}

/// A formatting instruction over a range of characters.
///
/// A [value] of `null` removes [type] over the range instead of applying it.
/// Marks are never trimmed or split once written: the format a character ends
/// up with is decided by comparing every mark that covers it.
class Mark {
  /// Creates a mark applying [value] of [type] between [start] and [end].
  const Mark({
    required this.start,
    required this.end,
    required this.type,
    required this.value,
  });

  /// Where the range begins.
  final MarkAnchor start;

  /// Where the range ends.
  final MarkAnchor end;

  /// What is being set, e.g. `'bold'` or `'link'`.
  final String type;

  /// What [type] is set to, or `null` to remove it over the range.
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is Mark &&
      other.start == start &&
      other.end == end &&
      other.type == type &&
      other.value == value;

  @override
  int get hashCode => Object.hash(start, end, type, value);

  @override
  String toString() => 'Mark($type=$value, $start..$end)';
}

/// A stretch of text that carries one value of one mark type.
///
/// Both offsets count **runes**, like every positional API of the handlers
/// that produce them, and [end] is exclusive.
class MarkSpan {
  /// Creates a span setting [type] to [value] over `[start, end)`.
  const MarkSpan({
    required this.start,
    required this.end,
    required this.type,
    required this.value,
  });

  /// The first rune the span covers.
  final int start;

  /// The rune after the last one the span covers.
  final int end;

  /// What is set, e.g. `'bold'` or `'link'`.
  final String type;

  /// What [type] is set to. Never `null`: a removal leaves no span behind.
  final Object value;

  @override
  bool operator ==(Object other) =>
      other is MarkSpan &&
      other.start == start &&
      other.end == end &&
      other.type == type &&
      other.value == value;

  @override
  int get hashCode => Object.hash(start, end, type, value);

  @override
  String toString() => 'MarkSpan($type=$value, $start..$end)';
}

/// Text together with the formatting that covers it.
class RichTextValue {
  /// Creates a value holding [text] and [spans].
  const RichTextValue({required this.text, required this.spans});

  /// The value of a document with no text and no formatting.
  const RichTextValue.empty()
      : text = '',
        spans = const [];

  /// The characters, with no formatting markers in them.
  final String text;

  /// The formatting, sorted by [MarkSpan.start] and then by
  /// [MarkSpan.type]. Never overlapping within one type.
  final List<MarkSpan> spans;

  @override
  bool operator ==(Object other) {
    if (other is! RichTextValue || other.text != text) {
      return false;
    }
    if (other.spans.length != spans.length) {
      return false;
    }
    for (var i = 0; i < spans.length; i += 1) {
      if (other.spans[i] != spans[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(spans));

  @override
  String toString() => 'RichTextValue("$text", $spans)';
}

/// One mark whose ends have been resolved to rune offsets.
class _Placed {
  _Placed(this.from, this.to, this.stamp, this.value);

  final int from;
  final int to;
  final OperationId stamp;
  final Object? value;
}

int _clamp(int value, int low, int high) {
  if (value < low) {
    return low;
  }
  return value > high ? high : value;
}

/// Turns the marks of a document into the spans that cover its text.
///
/// [resolveAnchor] gives the rune offset a [MarkAnchor] currently stands for,
/// or `null` for an anchor naming a character this document has not seen yet —
/// such a mark is left out until the character arrives. [length] is the text
/// length in runes.
///
/// Where several marks of one type cover the same character, the one with the
/// greatest [OperationId] wins; a winner whose [Mark.value] is `null` leaves
/// no span, which is how a removal takes formatting away without any mark
/// being trimmed. Values are compared with `==`, so a mark carrying a
/// collection is only merged with an equal one when that collection defines
/// equality.
///
/// The result is sorted and depends only on the marks, so two documents
/// holding the same marks produce the same spans.
List<MarkSpan> resolveMarkSpans({
  required Map<OperationId, Mark> marks,
  required int? Function(MarkAnchor anchor) resolveAnchor,
  required int length,
}) {
  final byType = <String, List<_Placed>>{};
  for (final entry in marks.entries) {
    final mark = entry.value;
    final from = resolveAnchor(mark.start);
    final to = resolveAnchor(mark.end);
    if (from == null || to == null) {
      continue;
    }
    final low = _clamp(from, 0, length);
    final high = _clamp(to, 0, length);
    if (low >= high) {
      continue;
    }
    byType
        .putIfAbsent(mark.type, () => <_Placed>[])
        .add(_Placed(low, high, entry.key, mark.value));
  }

  final spans = <MarkSpan>[];
  // Sorted, so the result does not depend on the order the marks arrived in.
  final types = byType.keys.toList()..sort();

  for (final type in types) {
    final placed = byType[type]!;
    final startsAt = <int, List<_Placed>>{};
    final endsAt = <int, List<_Placed>>{};
    final boundaries = SplayTreeSet<int>();

    for (final item in placed) {
      startsAt.putIfAbsent(item.from, () => <_Placed>[]).add(item);
      endsAt.putIfAbsent(item.to, () => <_Placed>[]).add(item);
      boundaries
        ..add(item.from)
        ..add(item.to);
    }

    // The active set is keyed by stamp, so the winner is its last key.
    final active = SplayTreeMap<OperationId, _Placed>();
    Object? runValue;
    var runStart = 0;

    for (final position in boundaries) {
      // Ends first: a range is half-open, so a mark ending here no longer
      // covers this character while one starting here already does.
      for (final item in endsAt[position] ?? const <_Placed>[]) {
        active.remove(item.stamp);
      }
      for (final item in startsAt[position] ?? const <_Placed>[]) {
        active[item.stamp] = item;
      }

      final winner = active.isEmpty ? null : active[active.lastKey()]!.value;
      if (winner == runValue) {
        continue;
      }
      if (runValue != null && position > runStart) {
        spans.add(
          MarkSpan(
            start: runStart,
            end: position,
            type: type,
            value: runValue,
          ),
        );
      }
      runValue = winner;
      runStart = position;
    }
  }

  spans.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.type.compareTo(b.type);
  });
  return spans;
}
