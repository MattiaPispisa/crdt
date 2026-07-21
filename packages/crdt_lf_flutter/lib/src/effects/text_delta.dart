import 'package:flutter/foundation.dart';

/// A single contiguous text edit: at [index], [deleted] code units are
/// removed and [inserted] is inserted.
///
/// This is the shape of every plain-text editing gesture (typing, backspace,
/// paste over a selection, autocorrect replacement), and it maps 1:1 onto the
/// `insert`/`delete` operations of the `crdt_lf` text handlers — no full-text
/// diff needed.
@immutable
class TextDelta {
  /// Creates a text delta.
  const TextDelta({
    required this.index,
    required this.deleted,
    required this.inserted,
  });

  /// Code-unit offset at which the edit happens.
  final int index;

  /// Number of code units removed at [index] (0 for a pure insertion).
  final int deleted;

  /// Text inserted at [index] (empty for a pure deletion).
  final String inserted;

  @override
  bool operator ==(Object other) =>
      other is TextDelta &&
      other.index == index &&
      other.deleted == deleted &&
      other.inserted == inserted;

  @override
  int get hashCode => Object.hash(index, deleted, inserted);

  @override
  String toString() =>
      'TextDelta(index: $index, deleted: $deleted, inserted: "$inserted")';
}

/// Computes the single contiguous [TextDelta] that turns [oldText] into
/// [newText], or `null` when they are equal.
///
/// Uses common prefix/suffix trimming — O(n) worst case and O(edit size) for
/// the typical edit-at-caret — instead of a full diff. The boundaries are
/// snapped so that a UTF-16 surrogate pair is never split between the kept
/// and the replaced region.
///
/// When the resulting collapsed [caret] (the selection offset *after* the
/// edit) is known, it disambiguates edits that touch a run of identical
/// characters: inserting a `\n` right before an existing `\n`, typing a space
/// before a space, etc. Prefix/suffix trimming alone is ambiguous there — the
/// two candidate positions produce the same string but a different edit — and
/// plain greedy trimming slides the edit *past* the caret, attaching the new
/// characters to the wrong side. Anchoring the edit so it ends at [caret]
/// keeps it where the user actually typed. Pass `null` (the default) to skip
/// this, e.g. when mapping a remote change rather than a local gesture.
///
/// Non-contiguous edits (which no single editing gesture produces) collapse
/// into one delta spanning both, which is still correct — just coarser.
TextDelta? computeTextDelta(String oldText, String newText, {int? caret}) {
  if (oldText == newText) {
    return null;
  }

  final oldLength = oldText.length;
  final newLength = newText.length;
  final maxPrefix = oldLength < newLength ? oldLength : newLength;

  var start = 0;
  while (start < maxPrefix &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }

  // Break the identical-run ambiguity toward the caret: the inserted run must
  // end at [caret], so the kept prefix cannot reach past it. A net insertion
  // of `k` characters starts `k` before the caret; a deletion/replacement
  // starts at the caret. We only ever *shorten* the prefix here — the freed
  // characters fold into the changed region, so the delta stays string-exact
  // — and then re-derive the suffix below against the corrected boundary.
  if (caret != null && caret >= 0 && caret <= newLength) {
    final netInsert = newLength > oldLength ? newLength - oldLength : 0;
    final cap = caret - netInsert;
    if (cap < start) {
      start = cap < 0 ? 0 : cap;
    }
  }

  var endOld = oldLength;
  var endNew = newLength;
  while (endOld > start &&
      endNew > start &&
      oldText.codeUnitAt(endOld - 1) == newText.codeUnitAt(endNew - 1)) {
    endOld--;
    endNew--;
  }

  // Never split a surrogate pair: widen the replaced region instead.
  if (start > 0 && _isHighSurrogate(oldText.codeUnitAt(start - 1))) {
    start--;
  }
  if (endOld < oldLength && _isLowSurrogate(oldText.codeUnitAt(endOld))) {
    endOld++;
    endNew++;
  }

  return TextDelta(
    index: start,
    deleted: endOld - start,
    inserted: newText.substring(start, endNew),
  );
}

/// Maps a caret/selection [offset] valid in the text *before* [delta] to the
/// equivalent offset in the text *after* it.
///
/// Offsets before the edit are unchanged, offsets inside the replaced region
/// snap to the end of the insertion, offsets after it shift by the length
/// difference. This keeps the caret visually anchored across a concurrent
/// remote edit.
int mapOffsetThroughDelta(int offset, TextDelta delta) {
  if (offset <= delta.index) {
    return offset;
  }
  if (offset <= delta.index + delta.deleted) {
    return delta.index + delta.inserted.length;
  }
  return offset + delta.inserted.length - delta.deleted;
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
