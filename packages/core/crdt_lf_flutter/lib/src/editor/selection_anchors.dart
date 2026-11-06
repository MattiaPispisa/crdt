// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';

/// The stable anchors of the selection of an editor, and what the editor
/// publishes of them.
///
/// It publishes each change while the editor has focus, and `null`s once when
/// the focus leaves. An unfocused editor keeps its selection.
class SelectionAnchors {
  /// Creates anchors that report what changes to `publish`.
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

  /// Anchors [selection], in UTF-16 code units of [text]; [positionAt] gives
  /// the anchor of a rune index.
  ///
  /// [text] must match the handler, or the anchors name the wrong elements.
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

  /// Whether the editor has focus.
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
