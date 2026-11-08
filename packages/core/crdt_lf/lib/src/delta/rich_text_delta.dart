// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/src/delta/handler_update.dart';
import 'package:crdt_lf/src/utils/attributes.dart';
import 'package:crdt_lf/src/utils/embed_data.dart';
import 'package:crdt_lf/src/utils/rune_offsets.dart';

/// A run of rich text whose runes all carry the same [attributes], or one
/// embed (see [embed]).
final class RichTextSpan {
  /// Creates a span of [text] with [attributes].
  RichTextSpan(this.text, [Map<String, Object?> attributes = const {}])
      : attributes = _freeze(attributes),
        embed = null;

  /// Creates the span of one embed with its [embed] data.
  ///
  /// Its [text] is [objectReplacement]. An embed span never fuses with a
  /// neighbour.
  RichTextSpan.embed(
    Map<String, Object?> embed, [
    Map<String, Object?> attributes = const {},
  ])  : text = objectReplacement,
        attributes = _freeze(attributes),
        embed = freezeEmbed(embed);

  /// U+FFFC, the text of an embed span and of an embed in the plain text.
  static const String objectReplacement = '\uFFFC';

  /// The runes of the span.
  final String text;

  /// The attributes of every rune of [text]; unmodifiable.
  final Map<String, Object?> attributes;

  /// The data of the embed, or `null` for text; unmodifiable.
  final Map<String, Object?>? embed;

  @override
  bool operator ==(Object other) =>
      other is RichTextSpan &&
      other.text == text &&
      sameAttributes(other.attributes, attributes) &&
      sameEmbed(other.embed, embed);

  @override
  int get hashCode =>
      Object.hash(text, _hashAttributes(attributes), hashEmbed(embed));

  @override
  String toString() => embed == null
      ? 'RichTextSpan(${_quote(text)}, $attributes)'
      : 'RichTextSpan.embed($embed, $attributes)';
}

/// One step of a [RichTextDelta].
///
/// Counts are in **runes**, in the coordinates of the text before the delta.
sealed class RichTextOp {
  /// Creates a step.
  const RichTextOp();

  /// How many runes the step covers.
  int get length;

  /// The attributes the step writes; unmodifiable.
  Map<String, Object?> get attributes;
}

/// Keeps [count] runes and writes [attributes] over them.
///
/// A key with a `null` value removes that key. With no attributes the runes
/// stay as they are.
final class RichTextRetain extends RichTextOp {
  /// Keeps [count] runes, formatted with [attributes].
  RichTextRetain(this.count, [Map<String, Object?> attributes = const {}])
      : assert(count >= 0, 'count cannot be negative'),
        attributes = _freeze(attributes);

  /// How many runes to keep.
  final int count;

  @override
  final Map<String, Object?> attributes;

  @override
  int get length => count;

  @override
  bool operator ==(Object other) =>
      other is RichTextRetain &&
      other.count == count &&
      sameAttributes(other.attributes, attributes);

  @override
  int get hashCode =>
      Object.hash(RichTextRetain, count, _hashAttributes(attributes));

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextRetain($count)'
      : 'RichTextRetain($count, $attributes)';
}

/// Puts [text] with [attributes] into the text at the current point.
final class RichTextInsert extends RichTextOp {
  /// Inserts [text] with [attributes].
  RichTextInsert(this.text, [Map<String, Object?> attributes = const {}])
      : length = RuneOffsets.length(text),
        attributes = _freeze(attributes);

  /// The runes to put in.
  final String text;

  @override
  final Map<String, Object?> attributes;

  @override
  final int length;

  @override
  bool operator ==(Object other) =>
      other is RichTextInsert &&
      other.text == text &&
      sameAttributes(other.attributes, attributes);

  @override
  int get hashCode =>
      Object.hash(RichTextInsert, text, _hashAttributes(attributes));

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextInsert(${_quote(text)})'
      : 'RichTextInsert(${_quote(text)}, $attributes)';
}

/// Puts one embed with [attributes] into the text at the current point.
final class RichTextInsertEmbed extends RichTextOp {
  /// Inserts the embed [embed] with [attributes].
  RichTextInsertEmbed(
    Map<String, Object?> embed, [
    Map<String, Object?> attributes = const {},
  ])  : embed = freezeEmbed(embed),
        attributes = _freeze(attributes);

  /// The data of the embed; unmodifiable.
  final Map<String, Object?> embed;

  @override
  final Map<String, Object?> attributes;

  @override
  int get length => 1;

  @override
  bool operator ==(Object other) =>
      other is RichTextInsertEmbed &&
      sameEmbed(other.embed, embed) &&
      sameAttributes(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
        RichTextInsertEmbed,
        hashEmbed(embed),
        _hashAttributes(attributes),
      );

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextInsertEmbed($embed)'
      : 'RichTextInsertEmbed($embed, $attributes)';
}

/// Keeps one embed, replaces its data with [embed] and writes [attributes].
final class RichTextUpdateEmbed extends RichTextOp {
  /// Replaces the data of the embed with [embed].
  RichTextUpdateEmbed(
    Map<String, Object?> embed, [
    Map<String, Object?> attributes = const {},
  ])  : embed = freezeEmbed(embed),
        attributes = _freeze(attributes);

  /// The new data of the embed; unmodifiable.
  final Map<String, Object?> embed;

  @override
  final Map<String, Object?> attributes;

  @override
  int get length => 1;

  @override
  bool operator ==(Object other) =>
      other is RichTextUpdateEmbed &&
      sameEmbed(other.embed, embed) &&
      sameAttributes(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
        RichTextUpdateEmbed,
        hashEmbed(embed),
        _hashAttributes(attributes),
      );

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextUpdateEmbed($embed)'
      : 'RichTextUpdateEmbed($embed, $attributes)';
}

/// Takes [count] runes out of the text at the current point.
final class RichTextDelete extends RichTextOp {
  /// Removes [count] runes.
  const RichTextDelete(this.count)
      : assert(count >= 0, 'count cannot be negative');

  /// How many runes to remove.
  final int count;

  @override
  int get length => count;

  @override
  Map<String, Object?> get attributes => const {};

  @override
  bool operator ==(Object other) =>
      other is RichTextDelete && other.count == count;

  @override
  int get hashCode => Object.hash(RichTextDelete, count);

  @override
  String toString() => 'RichTextDelete($count)';
}

/// How a rich text moved, as steps applied left to right.
///
/// Retain, insert and delete steps, counted in **runes**. A delta that only
/// formats is a run of [RichTextRetain] with attributes. An embed is one rune:
/// [RichTextInsertEmbed] puts one in, [RichTextUpdateEmbed] replaces its data.
final class RichTextDelta implements ComposableDelta<RichTextDelta> {
  /// Creates a delta from [ops], in normal form.
  ///
  /// The normal form drops empty steps and fuses neighbours of one kind with
  /// the same attributes. An insert next to a delete goes first, and a
  /// trailing retain without attributes goes. So two deltas with the same
  /// effect are equal.
  RichTextDelta(Iterable<RichTextOp> ops)
      : ops = List.unmodifiable(_normalize(ops));

  /// The delta that moves nothing.
  const RichTextDelta.empty() : ops = const [];

  /// The steps, applied left to right; unmodifiable.
  final List<RichTextOp> ops;

  @override
  bool get isEmpty => ops.isEmpty;

  /// Whether this delta moves something.
  bool get isNotEmpty => ops.isNotEmpty;

  /// {@macro composable_delta_compose}
  ///
  /// The attributes of [next] go over these. A `null` value stays a removal
  /// on a retain, and drops the key from an insert. An update of an inserted
  /// embed gives the insert with the new data; of two updates, the later
  /// one stays.
  @override
  RichTextDelta compose(RichTextDelta next) {
    final a = _OpCursor(ops);
    final b = _OpCursor(next.ops);
    final result = <RichTextOp>[];

    while (a.hasNext || b.hasNext) {
      if (b.hasNext && _isInsert(b.peek)) {
        result.add(b.take(b.peekLength));
        continue;
      }
      if (a.hasNext && a.peek is RichTextDelete) {
        result.add(a.take(a.peekLength));
        continue;
      }
      if (!a.hasNext) {
        result.add(b.take(b.peekLength));
        continue;
      }
      if (!b.hasNext) {
        result.add(a.take(a.peekLength));
        continue;
      }

      final length = a.peekLength < b.peekLength ? a.peekLength : b.peekLength;
      final mine = a.take(length);
      final theirs = b.take(length);

      switch ((mine, theirs)) {
        case (RichTextRetain(), RichTextRetain()):
          result.add(
            RichTextRetain(
              length,
              _composeAttributes(
                mine.attributes,
                theirs.attributes,
                keepNull: true,
              ),
            ),
          );
        case (final RichTextInsert insert, RichTextRetain()) ||
              (final RichTextInsert insert, RichTextUpdateEmbed()):
          result.add(
            RichTextInsert(
              insert.text,
              _composeAttributes(
                insert.attributes,
                theirs.attributes,
                keepNull: false,
              ),
            ),
          );
        case (final RichTextInsertEmbed insert, RichTextRetain()):
          result.add(
            RichTextInsertEmbed(
              insert.embed,
              _composeAttributes(
                insert.attributes,
                theirs.attributes,
                keepNull: false,
              ),
            ),
          );
        case (RichTextInsertEmbed(), final RichTextUpdateEmbed update):
          result.add(
            RichTextInsertEmbed(
              update.embed,
              _composeAttributes(
                mine.attributes,
                update.attributes,
                keepNull: false,
              ),
            ),
          );
        case (final RichTextUpdateEmbed update, RichTextRetain()):
          result.add(
            RichTextUpdateEmbed(
              update.embed,
              _composeAttributes(
                update.attributes,
                theirs.attributes,
                keepNull: true,
              ),
            ),
          );
        case (
            RichTextRetain() || RichTextUpdateEmbed(),
            final RichTextUpdateEmbed update
          ):
          result.add(
            RichTextUpdateEmbed(
              update.embed,
              _composeAttributes(
                mine.attributes,
                update.attributes,
                keepNull: true,
              ),
            ),
          );
        case (RichTextRetain() || RichTextUpdateEmbed(), RichTextDelete()):
          result.add(theirs);
        // Inserted here and removed by [next]: the two cancel out.
        case _:
          break;
      }
    }

    return RichTextDelta(result);
  }

  /// The spans [base] becomes once this delta is applied.
  ///
  /// [base] is left alone. Neighbour spans with the same attributes come out
  /// as one. The delta must stay within [base]: debug builds assert it.
  List<RichTextSpan> apply(List<RichTextSpan> base) {
    final document = RichTextDelta([
      for (final span in base)
        if (span.embed case final embed?)
          RichTextInsertEmbed(embed, span.attributes)
        else
          RichTextInsert(span.text, span.attributes),
    ]).compose(this);
    assert(
      document.ops.every(_isInsert),
      'the delta reaches past the end of the base spans',
    );
    return [
      for (final op in document.ops)
        if (op is RichTextInsert)
          RichTextSpan(op.text, op.attributes)
        else if (op is RichTextInsertEmbed)
          RichTextSpan.embed(op.embed, op.attributes),
    ];
  }

  /// The rune, in the new text, after the last insert or retain of this
  /// delta.
  int get changeEnd {
    var end = 0;
    for (final op in ops) {
      if (op is! RichTextDelete) {
        end += op.length;
      }
    }
    return end;
  }

  /// Where the rune [offset] ends up once this delta is applied.
  ///
  /// An offset exactly where text is inserted stays in front of it. One
  /// inside a removed run lands after what replaces it.
  int mapOffset(int offset) {
    var base = 0;
    var out = 0;
    var index = 0;

    while (index < ops.length) {
      final op = ops[index];
      switch (op) {
        case RichTextRetain() || RichTextUpdateEmbed():
          if (offset <= base + op.length) {
            return out + (offset - base);
          }
          base += op.length;
          out += op.length;
          index++;
        case RichTextInsert() || RichTextInsertEmbed():
          if (offset == base) {
            return out;
          }
          out += op.length;
          index++;
        case RichTextDelete():
          if (offset == base) {
            return out;
          }
          if (offset <= base + op.count) {
            return out;
          }
          base += op.count;
          index++;
      }
    }

    return out + (offset - base);
  }

  @override
  bool operator ==(Object other) {
    if (other is! RichTextDelta || other.ops.length != ops.length) {
      return false;
    }
    for (var i = 0; i < ops.length; i++) {
      if (other.ops[i] != ops[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ops);

  @override
  String toString() => 'RichTextDelta($ops)';
}

final class _OpCursor {
  _OpCursor(this._ops);

  final List<RichTextOp> _ops;
  int _index = 0;
  int _offset = 0;

  // A UTF-16 offset into the insert under the cursor, kept with [_offset].
  int _unit = 0;

  bool get hasNext => _index < _ops.length;

  RichTextOp get peek => _ops[_index];

  int get peekLength => _ops[_index].length - _offset;

  RichTextOp take(int length) {
    final op = _ops[_index];
    final RichTextOp piece;
    switch (op) {
      case RichTextRetain():
        piece = _offset == 0 && length == op.count
            ? op
            : RichTextRetain(length, op.attributes);
      case RichTextDelete():
        piece = RichTextDelete(length);
      case RichTextInsert():
        if (_offset == 0 && length == op.length) {
          piece = op;
        } else {
          final end = RuneOffsets.skip(op.text, _unit, length);
          piece = RichTextInsert(op.text.substring(_unit, end), op.attributes);
          _unit = end;
        }
      case RichTextInsertEmbed() || RichTextUpdateEmbed():
        piece = op;
    }

    _offset += length;
    if (_offset >= op.length) {
      _index++;
      _offset = 0;
      _unit = 0;
    }
    return piece;
  }
}

List<RichTextOp> _normalize(Iterable<RichTextOp> ops) {
  final result = <RichTextOp>[];
  for (final op in ops) {
    _push(result, op);
  }
  while (result.isNotEmpty) {
    final last = result.last;
    if (last is! RichTextRetain || last.attributes.isNotEmpty) {
      break;
    }
    result.removeLast();
  }
  return result;
}

void _push(List<RichTextOp> ops, RichTextOp op) {
  if (op.length == 0) {
    return;
  }
  if (ops.isEmpty) {
    ops.add(op);
    return;
  }
  final last = ops.last;
  if (last is RichTextDelete && op is RichTextDelete) {
    ops[ops.length - 1] = RichTextDelete(last.count + op.count);
    return;
  }
  // An insert next to a delete goes first: the two orders mean the same.
  if (last is RichTextDelete && _isInsert(op)) {
    ops.removeLast();
    _push(ops, op);
    ops.add(last);
    return;
  }
  if (last is RichTextRetain &&
      op is RichTextRetain &&
      sameAttributes(last.attributes, op.attributes)) {
    ops[ops.length - 1] = RichTextRetain(
      last.count + op.count,
      last.attributes,
    );
    return;
  }
  if (last is RichTextInsert &&
      op is RichTextInsert &&
      sameAttributes(last.attributes, op.attributes)) {
    ops[ops.length - 1] = RichTextInsert(
      last.text + op.text,
      last.attributes,
    );
    return;
  }
  ops.add(op);
}

bool _isInsert(RichTextOp op) =>
    op is RichTextInsert || op is RichTextInsertEmbed;

Map<String, Object?> _composeAttributes(
  Map<String, Object?> a,
  Map<String, Object?> b, {
  required bool keepNull,
}) {
  if (b.isEmpty && (keepNull || !a.containsValue(null))) {
    return a;
  }
  final result = <String, Object?>{...a, ...b};
  if (!keepNull) {
    result.removeWhere((_, value) => value == null);
  }
  return result;
}

// Attributes are frozen once, then shared by the spans and the deltas.
final Expando<bool> _frozenAttributes = Expando('frozen attributes');

Map<String, Object?> _freeze(Map<String, Object?> attributes) {
  if (attributes.isEmpty) {
    return const {};
  }
  if (_frozenAttributes[attributes] ?? false) {
    return attributes;
  }
  final copy = Map<String, Object?>.unmodifiable(attributes);
  _frozenAttributes[copy] = true;
  return copy;
}

int _hashAttributes(Map<String, Object?> attributes) => Object.hashAllUnordered(
      attributes.entries.map((entry) => Object.hash(entry.key, entry.value)),
    );

String _quote(String text) => '"$text"';
