// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

// The tree half of the delta, with the attributes the inserted text has
// once the operation is in.
RichTextDelta _richDelta(
  RichTextState state,
  Operation operation,
  SequenceDelta<String>? delta,
) {
  if (delta == null || delta.isEmpty) {
    return const RichTextDelta.empty();
  }
  // Resolved at the first insert: a delete-only delta needs no attributes.
  _ResolvedMarks? resolved;
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
        final runs = (resolved ??= state._resolved()).runsIn(out, end);
        if (operation is _FugueRichTextEmbedOperation) {
          ops.add(RichTextInsertEmbed(operation.data, runs.single.attributes));
          out = end;
          continue;
        }
        for (final run in runs) {
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

// The place of the embed, when the update wins.
RichTextDelta _embedUpdateDelta(
  RichTextState state,
  _FugueRichTextEmbedUpdateOperation operation,
) {
  final index = state._tree.liveIndexAfter(operation.element)! - 1;
  return RichTextDelta([
    RichTextRetain(index),
    RichTextUpdateEmbed(operation.data),
  ]);
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
