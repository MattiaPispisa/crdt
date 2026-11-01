// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

// The tree half of the delta, with the attributes the inserted text has
// once the operation is in.
RichTextDelta _richDelta(RichTextState state, SequenceDelta<String>? delta) {
  if (delta == null || delta.isEmpty) {
    return const RichTextDelta.empty();
  }
  final resolved = state._resolved();
  final ops = <RichTextOp>[];
  var out = 0;
  for (final op in delta.ops) {
    switch (op) {
      case SeqRetain<String>():
        ops.add(RichTextRetain(op.count));
        out += op.count;
      case SeqDelete<String>():
        ops.add(RichTextDelete(op.count));
      case SeqInsert<String>():
        final end = out + op.values.length;
        for (final run in resolved.runsIn(out, end)) {
          ops.add(
            RichTextInsert(
              op.values.sublist(run.start - out, run.end - out).join(),
              run.attributes,
            ),
          );
        }
        out = end;
      case SeqMove<String>():
        throw UnsupportedError('a rich text never moves an element');
    }
  }
  return RichTextDelta(ops);
}

// The covered places whose value for the key of the mark moved.
RichTextDelta _markDelta(
  RichTextState state,
  _FugueRichTextMarkOperation operation,
) {
  final tree = state._tree;
  final from = operation.start.liveStart(tree);
  final to = operation.end.liveEnd(tree, tree.liveLength);
  if (from == null || to == null || from >= to) {
    state._addMark(operation);
    return const RichTextDelta.empty();
  }

  final key = operation.key;
  final was = state._resolved().keyRuns(key, from, to);
  if (!state._addMark(operation)) {
    return const RichTextDelta.empty();
  }
  final now = state._resolved().keyRuns(key, from, to);
  final ops = <RichTextOp>[];
  var cursor = 0;
  var position = from;
  var i = 0;
  var j = 0;
  while (position < to) {
    final end = was[i].end < now[j].end ? was[i].end : now[j].end;
    if (was[i].value != now[j].value) {
      ops
        ..add(RichTextRetain(position - cursor))
        ..add(RichTextRetain(end - position, {key: now[j].value}));
      cursor = end;
    }
    position = end;
    if (was[i].end == end) {
      i++;
    }
    if (now[j].end == end) {
      j++;
    }
  }
  return RichTextDelta(ops);
}
