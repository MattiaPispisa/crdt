// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:flutter/widgets.dart';

/// The stable anchors of the selection of a text field, and what is published
/// of them.
///
/// The anchors steer `adoptedValue` always, but they are the collaborator's
/// cursor only while the field has focus: an unfocused field keeps its
/// selection.
class SelectionAnchors {
  /// Creates anchors that report changes to `publish`.
  SelectionAnchors(this._publish);

  final void Function(FugueElementID? base, FugueElementID? extent) _publish;

  FugueElementID? _base;
  FugueElementID? _extent;
  bool _hasFocus = false;
  FugueElementID? _publishedBase;
  FugueElementID? _publishedExtent;

  /// The anchor of the selection base.
  FugueElementID? get base => _base;

  /// The anchor of the selection extent.
  FugueElementID? get extent => _extent;

  /// Replaces the anchors.
  void update(FugueElementID? base, FugueElementID? extent) {
    if (base == _base && extent == _extent) {
      return;
    }
    _base = base;
    _extent = extent;
    _publishIfChanged();
  }

  /// Drops the anchors.
  void clear() => update(null, null);

  /// Anchors [selection] of [text]; [positionAt] gives the anchor of a rune
  /// index.
  void capture(
    TextSelection selection,
    String text,
    FugueElementID? Function(int rune) positionAt,
  ) {
    // Selection offsets are code units; the handler anchors by rune.
    FugueElementID? anchor(int offset) =>
        offset < 0 ? null : positionAt(RuneOffsets.runeIndex(text, offset));
    update(anchor(selection.baseOffset), anchor(selection.extentOffset));
  }

  /// Whether the field has focus.
  bool get hasFocus => _hasFocus;

  set hasFocus(bool hasFocus) {
    if (_hasFocus == hasFocus) {
      return;
    }
    _hasFocus = hasFocus;
    _publishIfChanged();
  }

  void _publishIfChanged() {
    final base = _hasFocus ? _base : null;
    final extent = _hasFocus ? _extent : null;
    if (base == _publishedBase && extent == _publishedExtent) {
      return;
    }
    _publishedBase = base;
    _publishedExtent = extent;
    _publish(base, extent);
  }
}

/// [delta], computed against [committed], moved onto [current].
///
/// A remote change that landed while local edits were pending (only during a
/// composition) shifted the text. Best effort: the CRDT does the merging.
TextDelta rebaseDelta(TextDelta delta, String committed, String current) {
  final remote = computeTextDelta(committed, current)!;
  final index =
      mapOffsetThroughDelta(delta.index, remote).clamp(0, current.length);
  final deletable = current.length - index;
  return TextDelta(
    index: index,
    deleted: delta.deleted > deletable ? deletable : delta.deleted,
    inserted: delta.inserted,
  );
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
