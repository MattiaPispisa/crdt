import 'package:crdt_lf/src/delta/handler_update.dart';
import 'package:crdt_lf/src/utils/rune_offsets.dart';

/// One step of a [SequenceDelta].
///
/// Every count a step carries is expressed in the coordinates of the sequence
/// **before** the delta is applied. Steps run left to right.
sealed class SeqOp<T> {
  /// Creates a step.
  const SeqOp();
}

/// Keeps [count] elements as they are and moves past them.
final class SeqRetain<T> extends SeqOp<T> {
  /// Keeps [count] elements.
  const SeqRetain(this.count) : assert(count >= 0, 'count cannot be negative');

  /// How many elements to keep.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SeqRetain<T> && other.count == count;

  @override
  int get hashCode => Object.hash(SeqRetain<T>, count);

  @override
  String toString() => 'SeqRetain($count)';
}

/// Puts [values] into the sequence at the current point.
final class SeqInsert<T> extends SeqOp<T> {
  /// Inserts [values].
  const SeqInsert(this.values);

  /// The elements to put in.
  final List<T> values;

  @override
  bool operator ==(Object other) =>
      other is SeqInsert<T> && _listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(SeqInsert<T>, Object.hashAll(values));

  @override
  String toString() => 'SeqInsert($values)';
}

/// Takes [count] elements out of the sequence at the current point.
final class SeqDelete<T> extends SeqOp<T> {
  /// Removes [count] elements.
  const SeqDelete(this.count) : assert(count >= 0, 'count cannot be negative');

  /// How many elements to remove.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SeqDelete<T> && other.count == count;

  @override
  int get hashCode => Object.hash(SeqDelete<T>, count);

  @override
  String toString() => 'SeqDelete($count)';
}

/// Moves the element at [from] to [to], keeping its identity.
///
/// Only `CRDTFugueMovableListHandler` emits this. A delete followed by an
/// insert would describe the same result, but it would throw away the identity
/// that handler exists to preserve — a list view would rebuild the row instead
/// of animating it.
///
/// A [SequenceDelta] that holds a move holds nothing else, and such a delta
/// supports neither [SequenceDelta.compose] nor [SequenceDelta.mapOffset].
final class SeqMove<T> extends SeqOp<T> {
  /// Moves the element at [from] to [to].
  const SeqMove({required this.from, required this.to})
      : assert(from >= 0, 'from cannot be negative'),
        assert(to >= 0, 'to cannot be negative');

  /// Where the element sits before the move.
  final int from;

  /// Where the element sits after the move.
  final int to;

  @override
  bool operator ==(Object other) =>
      other is SeqMove<T> && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(SeqMove<T>, from, to);

  @override
  String toString() => 'SeqMove($from -> $to)';
}

/// How a sequence handler's value moved, as a list of steps applied left to
/// right.
///
/// The shape is the one every editor binding already knows: retain, insert,
/// delete, in the coordinates of the sequence before the delta.
///
/// The text handlers use `SequenceDelta<String>` where one element is one
/// **rune**, matching the way they index their text.
final class SequenceDelta<T> implements ComposableDelta<SequenceDelta<T>> {
  /// Creates a delta from [ops].
  SequenceDelta(this.ops)
      : assert(
          ops.every((op) => op is! SeqMove<T>) ||
              (ops.length == 1 && ops.first is SeqMove<T>),
          'a delta that holds a move holds nothing else',
        );

  /// The delta that moves nothing.
  const SequenceDelta.empty() : ops = const [];

  /// The steps, applied left to right.
  final List<SeqOp<T>> ops;

  /// Whether this delta moves nothing.
  bool get isEmpty => ops.isEmpty;

  /// Whether this delta moves something.
  bool get isNotEmpty => ops.isNotEmpty;

  /// The delta that has the same effect as this one followed by [next].
  ///
  /// [next] is read in the coordinates of the sequence **after** this delta,
  /// which is what makes the result equal to applying the two in order.
  ///
  /// This is what turns the per-operation deltas of a transaction into the one
  /// event a compacted change carries.
  ///
  /// Throws an [UnsupportedError] when either side holds a [SeqMove].
  @override
  SequenceDelta<T> compose(SequenceDelta<T> next) {
    final a = _OpCursor<T>(ops)..guardNoMove();
    final b = _OpCursor<T>(next.ops)..guardNoMove();
    final result = <SeqOp<T>>[];

    while (a.hasNext || b.hasNext) {
      // An insert of [next] lands in the output of this delta, so nothing of
      // this delta can consume it.
      if (b.hasNext && b.peek is SeqInsert<T>) {
        _push(result, b.take(b.peekLength));
        continue;
      }
      // A delete of this delta consumed the base already, so [next] never saw
      // those elements.
      if (a.hasNext && a.peek is SeqDelete<T>) {
        _push(result, a.take(a.peekLength));
        continue;
      }
      if (!a.hasNext) {
        // Past what this delta covers: [next] acts on the untouched tail.
        _push(result, b.take(b.peekLength));
        continue;
      }
      if (!b.hasNext) {
        _push(result, a.take(a.peekLength));
        continue;
      }

      final length = a.peekLength < b.peekLength ? a.peekLength : b.peekLength;
      final mine = a.take(length);
      final theirs = b.take(length);

      if (theirs is SeqRetain<T>) {
        // Kept by [next]: whatever this delta did survives.
        _push(result, mine);
      } else if (mine is SeqRetain<T>) {
        // Kept here, removed by [next]: the base element goes.
        _push(result, theirs);
      }
      // Inserted here and removed by [next]: the two cancel out.
    }

    return SequenceDelta<T>(_chop(result));
  }

  /// The sequence [base] becomes once this delta is applied.
  ///
  /// [base] is left alone; the result is a new list.
  List<T> apply(List<T> base) {
    if (ops.length == 1) {
      final only = ops.first;
      if (only is SeqMove<T>) {
        final result = List<T>.of(base);
        final moved = result.removeAt(only.from);
        result.insert(only.to, moved);
        return result;
      }
    }

    final result = <T>[];
    var index = 0;
    for (final op in ops) {
      switch (op) {
        case SeqRetain<T>():
          result.addAll(base.getRange(index, index + op.count));
          index += op.count;
        case SeqInsert<T>():
          result.addAll(op.values);
        case SeqDelete<T>():
          index += op.count;
        case SeqMove<T>():
          throw UnsupportedError('a move must be the only op of its delta');
      }
    }
    result.addAll(base.skip(index));
    return result;
  }

  /// Where [offset] ends up once this delta is applied.
  ///
  /// [offset] counts elements of the sequence before the delta. An offset that
  /// sits exactly where something is inserted stays in front of it; an offset
  /// inside a removed run collapses to the point of the splice.
  ///
  /// This is what places a caret after a remote edit.
  ///
  /// Throws an [UnsupportedError] when this delta holds a [SeqMove].
  int mapOffset(int offset) {
    var base = 0;
    var out = 0;
    var index = 0;

    while (index < ops.length) {
      final op = ops[index];
      switch (op) {
        case SeqRetain<T>():
          if (offset <= base + op.count) {
            return out + (offset - base);
          }
          base += op.count;
          out += op.count;
          index++;
        case SeqInsert<T>():
          // Right here: stay in front of what is put in. The retain arm above
          // already answers this when a retain leads, and a delta that starts
          // at zero carries none — without this the answer would depend on
          // that.
          if (offset == base) {
            return out;
          }
          out += op.values.length;
          index++;
        case SeqDelete<T>():
          // At the front of the removed run, so in front of what replaces it —
          // the same answer a leading retain would have given.
          if (offset == base) {
            return out;
          }
          if (offset <= base + op.count) {
            // Inside the removed run: land on the splice, past whatever takes
            // its place.
            var ahead = index + 1;
            while (ahead < ops.length) {
              final next = ops[ahead];
              if (next is! SeqInsert<T>) {
                break;
              }
              out += next.values.length;
              ahead++;
            }
            return out;
          }
          base += op.count;
          index++;
        case SeqMove<T>():
          throw UnsupportedError('a move cannot map an offset');
      }
    }

    return out + (offset - base);
  }

  @override
  bool operator ==(Object other) =>
      other is SequenceDelta<T> && _listEquals(other.ops, ops);

  @override
  int get hashCode => Object.hashAll(ops);

  @override
  String toString() => 'SequenceDelta($ops)';
}

/// String conveniences for the delta shape the text handlers emit.
extension SequenceDeltaText on SequenceDelta<String> {
  /// The text [base] becomes once this delta is applied.
  ///
  /// [base] is split by rune, the unit the text handlers index by.
  String applyToText(String base) {
    if (ops.isEmpty) {
      return base;
    }

    // Splice, rather than take the string apart into one-character pieces and
    // put it back together: a delta usually touches a handful of characters,
    // and a document has no reason to pay an allocation per character of it.
    final buffer = StringBuffer();
    var offset = 0;

    for (final op in ops) {
      switch (op) {
        case SeqRetain<String>():
          final end = RuneOffsets.skip(base, offset, op.count);
          assert(_reached(offset, end, op.count), _pastTheEnd);
          buffer.write(base.substring(offset, end));
          offset = end;
        case SeqInsert<String>():
          for (final value in op.values) {
            buffer.write(value);
          }
        case SeqDelete<String>():
          final end = RuneOffsets.skip(base, offset, op.count);
          assert(_reached(offset, end, op.count), _pastTheEnd);
          offset = end;
        case SeqMove<String>():
          throw UnsupportedError('a move must be the only op of its delta');
      }
    }

    return (buffer..write(base.substring(offset))).toString();
  }
}

const _pastTheEnd = 'the delta reaches past the end of the base text';

/// Whether skipping from [from] to [to] could have covered [count] runes.
///
/// A delta that reaches past the end of its base was built against a different
/// text. [RuneOffsets.skip] clamps there instead of failing, so the result
/// comes out silently short — and a consumer that carries its length by
/// arithmetic never notices, because it trusts the counts and never looks at
/// the base.
///
/// One rune is one code unit or two, so covering [count] runes always advances
/// at least [count] code units: advancing fewer proves the skip ran out. The
/// test is O(1) — [SequenceDeltaText.applyToText] costs the size of the edit,
/// and a check that walked the whole base would be the very cost it exists to
/// avoid. It is therefore one-sided: it never accuses a sound delta, and it
/// lets a short one through when surrogate pairs leave enough code units
/// behind.
bool _reached(int from, int to, int count) => to - from >= count;

/// String conveniences for the insert step the text handlers emit.
extension SeqInsertText on SeqInsert<String> {
  /// The inserted elements as one string.
  String get text => values.join();
}

/// Inserts [text] one rune at a time.
SeqInsert<String> seqInsertText(String text) =>
    SeqInsert<String>(text.runes.map(String.fromCharCode).toList());

/// Walks a list of [SeqOp], handing out pieces of the op it sits on.
final class _OpCursor<T> {
  _OpCursor(this._ops);

  final List<SeqOp<T>> _ops;
  int _index = 0;
  int _offset = 0;

  bool get hasNext => _index < _ops.length;

  SeqOp<T> get peek => _ops[_index];

  int get peekLength => _lengthOf(_ops[_index]) - _offset;

  void guardNoMove() {
    for (final op in _ops) {
      if (op is SeqMove<T>) {
        throw UnsupportedError('a move cannot be composed');
      }
    }
  }

  SeqOp<T> take(int length) {
    final op = _ops[_index];
    final SeqOp<T> piece;
    switch (op) {
      case SeqRetain<T>():
        piece = SeqRetain<T>(length);
      case SeqDelete<T>():
        piece = SeqDelete<T>(length);
      case SeqInsert<T>():
        piece = SeqInsert<T>(op.values.sublist(_offset, _offset + length));
      case SeqMove<T>():
        throw UnsupportedError('a move cannot be composed');
    }

    _offset += length;
    if (_offset >= _lengthOf(op)) {
      _index++;
      _offset = 0;
    }
    return piece;
  }
}

int _lengthOf<T>(SeqOp<T> op) => switch (op) {
      SeqRetain<T>() => op.count,
      SeqDelete<T>() => op.count,
      SeqInsert<T>() => op.values.length,
      SeqMove<T>() => 0,
    };

/// Appends [op], folding it into the last step when they are of one kind.
void _push<T>(List<SeqOp<T>> ops, SeqOp<T> op) {
  if (_lengthOf(op) == 0) {
    return;
  }
  if (ops.isNotEmpty) {
    final last = ops.last;
    if (last is SeqRetain<T> && op is SeqRetain<T>) {
      ops[ops.length - 1] = SeqRetain<T>(last.count + op.count);
      return;
    }
    if (last is SeqDelete<T> && op is SeqDelete<T>) {
      ops[ops.length - 1] = SeqDelete<T>(last.count + op.count);
      return;
    }
    if (last is SeqInsert<T> && op is SeqInsert<T>) {
      ops[ops.length - 1] = SeqInsert<T>([...last.values, ...op.values]);
      return;
    }
  }
  ops.add(op);
}

/// Drops a trailing retain: keeping the tail as it is moves nothing.
List<SeqOp<T>> _chop<T>(List<SeqOp<T>> ops) {
  if (ops.isNotEmpty && ops.last is SeqRetain<T>) {
    return ops.sublist(0, ops.length - 1);
  }
  return ops;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
