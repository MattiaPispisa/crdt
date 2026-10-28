// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/src/delta/handler_update.dart';
import 'package:crdt_lf/src/utils/rune_offsets.dart';

final class RichTextSpan {
  RichTextSpan(this.text, [Map<String, Object?> attributes = const {}])
      : attributes = _freeze(attributes);

  final String text;
  final Map<String, Object?> attributes;

  @override
  bool operator ==(Object other) =>
      other is RichTextSpan &&
      other.text == text &&
      _sameAttributes(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(text, _hashAttributes(attributes));

  @override
  String toString() => 'RichTextSpan(${_quote(text)}, $attributes)';
}

sealed class RichTextOp {
  const RichTextOp();

  int get length;

  Map<String, Object?> get attributes;
}

final class RichTextRetain extends RichTextOp {
  RichTextRetain(this.count, [Map<String, Object?> attributes = const {}])
      : assert(count >= 0, 'count cannot be negative'),
        attributes = _freeze(attributes);

  final int count;

  @override
  final Map<String, Object?> attributes;

  @override
  int get length => count;

  @override
  bool operator ==(Object other) =>
      other is RichTextRetain &&
      other.count == count &&
      _sameAttributes(other.attributes, attributes);

  @override
  int get hashCode =>
      Object.hash(RichTextRetain, count, _hashAttributes(attributes));

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextRetain($count)'
      : 'RichTextRetain($count, $attributes)';
}

final class RichTextInsert extends RichTextOp {
  RichTextInsert(this.text, [Map<String, Object?> attributes = const {}])
      : length = RuneOffsets.length(text),
        attributes = _freeze(attributes);

  final String text;

  @override
  final Map<String, Object?> attributes;

  @override
  final int length;

  @override
  bool operator ==(Object other) =>
      other is RichTextInsert &&
      other.text == text &&
      _sameAttributes(other.attributes, attributes);

  @override
  int get hashCode =>
      Object.hash(RichTextInsert, text, _hashAttributes(attributes));

  @override
  String toString() => attributes.isEmpty
      ? 'RichTextInsert(${_quote(text)})'
      : 'RichTextInsert(${_quote(text)}, $attributes)';
}

final class RichTextDelete extends RichTextOp {
  const RichTextDelete(this.count)
      : assert(count >= 0, 'count cannot be negative');

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

final class RichTextDelta implements ComposableDelta<RichTextDelta> {
  RichTextDelta(Iterable<RichTextOp> ops)
      : ops = List.unmodifiable(_normalize(ops));

  const RichTextDelta.empty() : ops = const [];

  final List<RichTextOp> ops;

  @override
  bool get isEmpty => ops.isEmpty;

  bool get isNotEmpty => ops.isNotEmpty;

  @override
  RichTextDelta compose(RichTextDelta next) {
    final a = _OpCursor(ops);
    final b = _OpCursor(next.ops);
    final result = <RichTextOp>[];

    while (a.hasNext || b.hasNext) {
      if (b.hasNext && b.peek is RichTextInsert) {
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

      switch (theirs) {
        case RichTextRetain():
          switch (mine) {
            case RichTextRetain():
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
            case RichTextInsert():
              result.add(
                RichTextInsert(
                  mine.text,
                  _composeAttributes(
                    mine.attributes,
                    theirs.attributes,
                    keepNull: false,
                  ),
                ),
              );
            case RichTextDelete():
              break;
          }
        case RichTextDelete():
          if (mine is RichTextRetain) {
            result.add(theirs);
          }
        case RichTextInsert():
          break;
      }
    }

    return RichTextDelta(result);
  }

  List<RichTextSpan> apply(List<RichTextSpan> base) {
    final document = RichTextDelta([
      for (final span in base) RichTextInsert(span.text, span.attributes),
    ]).compose(this);
    assert(
      document.ops.every((op) => op is RichTextInsert),
      'the delta reaches past the end of the base spans',
    );
    return [
      for (final op in document.ops)
        if (op is RichTextInsert) RichTextSpan(op.text, op.attributes),
    ];
  }

  int mapOffset(int offset) {
    var base = 0;
    var out = 0;
    var index = 0;

    while (index < ops.length) {
      final op = ops[index];
      switch (op) {
        case RichTextRetain():
          if (offset <= base + op.count) {
            return out + (offset - base);
          }
          base += op.count;
          out += op.count;
          index++;
        case RichTextInsert():
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
            var ahead = index + 1;
            while (ahead < ops.length) {
              final next = ops[ahead];
              if (next is! RichTextInsert) {
                break;
              }
              out += next.length;
              ahead++;
            }
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
  if (last is RichTextDelete && op is RichTextInsert) {
    ops.removeLast();
    _push(ops, op);
    ops.add(last);
    return;
  }
  if (last is RichTextRetain &&
      op is RichTextRetain &&
      _sameAttributes(last.attributes, op.attributes)) {
    ops[ops.length - 1] = RichTextRetain(
      last.count + op.count,
      last.attributes,
    );
    return;
  }
  if (last is RichTextInsert &&
      op is RichTextInsert &&
      _sameAttributes(last.attributes, op.attributes)) {
    ops[ops.length - 1] = RichTextInsert(
      last.text + op.text,
      last.attributes,
    );
    return;
  }
  ops.add(op);
}

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

Map<String, Object?> _freeze(Map<String, Object?> attributes) =>
    attributes.isEmpty ? const {} : Map.unmodifiable(attributes);

bool _sameAttributes(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _hashAttributes(Map<String, Object?> attributes) => Object.hashAllUnordered(
      attributes.entries.map((entry) => Object.hash(entry.key, entry.value)),
    );

String _quote(String text) => '"$text"';
