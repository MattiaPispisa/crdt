// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:flutter/widgets.dart';

/// [delta], computed against [committed], moved onto [current].
///
/// A remote change that landed while local edits were pending (only during a
/// composition) shifted the text. What it put inside the deleted range stays,
/// so the range can come back in two regions, as offsets into [current]. Best
/// effort: the CRDT does the merging.
List<TextDelta> rebaseDelta(
  TextDelta delta,
  String committed,
  String current,
) {
  final remote = computeTextDelta(committed, current)!;
  final end = delta.index + delta.deleted;
  final remoteEnd = remote.index + remote.deleted;
  final rightAt = max(delta.index, remoteEnd);
  final rightStart = rightAt + remote.inserted.length - remote.deleted;

  final left = min(end, remote.index) - delta.index;
  final right = end - rightAt;
  final inserted = delta.inserted;
  if (left > 0 && right > 0) {
    return [
      TextDelta(index: delta.index, deleted: left, inserted: inserted),
      TextDelta(index: rightStart, deleted: right, inserted: ''),
    ];
  }
  if (left > 0) {
    return [TextDelta(index: delta.index, deleted: left, inserted: inserted)];
  }
  if (right > 0) {
    return [TextDelta(index: rightStart, deleted: right, inserted: inserted)];
  }
  final index =
      mapOffsetThroughDelta(delta.index, remote).clamp(0, current.length);
  return [TextDelta(index: index, deleted: 0, inserted: inserted)];
}

/// The value of a field after its text became [merged], with the caret and the
/// selection kept visually anchored.
///
/// Three ways to place an offset, best first:
///
/// 1. its **stable position**, the identity of the element left of it, when
///    [resolve] knows it (a Fugue handler);
/// 2. [mapReported], which carries a rune through the delta the handler
///    published, exact even when the change touched several regions;
/// 3. a diff of the two texts, which collapses several regions into one span.
///    Best effort, and only used when the handler asked for a fresh read.
TextEditingValue adoptedValue({
  required TextEditingValue old,
  required String merged,
  required FugueElementID? baseAnchor,
  required FugueElementID? extentAnchor,
  required int? Function(FugueElementID anchor) resolve,
  int Function(int rune)? mapReported,
}) {
  TextDelta? diffed;
  int map(int offset, FugueElementID? anchor) {
    if (offset < 0) {
      // No selection (field never touched): keep it that way. Turning it into
      // a caret would publish a phantom cursor on adopt.
      return offset;
    }
    if (anchor != null) {
      final resolved = resolve(anchor);
      if (resolved != null) {
        // A rune index: back to a code-unit offset for the selection.
        return RuneOffsets.utf16Offset(merged, resolved);
      }
    }
    if (mapReported != null) {
      // The handler counts runes, the field counts code units.
      final rune = RuneOffsets.runeIndex(old.text, offset);
      return RuneOffsets.utf16Offset(merged, mapReported(rune))
          .clamp(0, merged.length);
    }
    diffed ??= computeTextDelta(old.text, merged)!;
    return mapOffsetThroughDelta(offset, diffed!).clamp(0, merged.length);
  }

  // A composition in progress spans code units that just moved. Carry it, or a
  // remote change throws away what the user is typing.
  var composing = TextRange.empty;
  if (old.composing.isValid) {
    final start = map(old.composing.start, null);
    final end = map(old.composing.end, null);
    if (start < end) {
      composing = TextRange(start: start, end: end);
    }
  }

  return TextEditingValue(
    text: merged,
    selection: TextSelection(
      baseOffset: map(old.selection.baseOffset, baseAnchor),
      extentOffset: map(old.selection.extentOffset, extentAnchor),
    ),
    composing: composing,
  );
}

/// Whether [dropped] holds nothing but a write of [deleted] and [inserted]
/// runes.
///
/// A change of another writer adds to the totals, even one that keeps the
/// length of the text.
bool echoesSequence(
  List<SequenceDelta<String>> dropped, {
  required int deleted,
  required int inserted,
}) {
  var totalIn = 0;
  var totalOut = 0;
  for (final delta in dropped) {
    for (final op in delta.ops) {
      switch (op) {
        case SeqInsert<String>():
          totalIn += op.values.length;
        case SeqDelete<String>():
          totalOut += op.count;
        case SeqRetain<String>():
        case SeqMove<String>():
          break;
      }
    }
  }
  return totalIn == inserted && totalOut == deleted;
}
