// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Paints the carets and selections of remote collaborators over the
/// `QuillEditor` inside [child].
///
/// It is a `CrdtTextCursorsOverlay` that finds the editor of Quill: anchors,
/// labels, motion and repaints work the same. Publish the anchors with
/// `CrdtQuillBinder.onSelectionAnchorsChanged`.
///
/// Cursors change often: give the editor a `FocusNode` that outlives the
/// build, or each rebuild drops the keyboard.
///
/// ```dart
/// CrdtQuillBinder(
///   id: 'page',
///   controller: controller,
///   onSelectionAnchorsChanged: publishPresence,
///   child: CrdtQuillCursorsOverlay(
///     id: 'page',
///     cursors: cursors, // from your presence channel
///     child: QuillEditor.basic(
///       controller: controller,
///       focusNode: focusNode,
///       scrollController: scrollController,
///     ),
///   ),
/// );
/// ```
class CrdtQuillCursorsOverlay extends StatelessWidget {
  /// Creates an overlay of [cursors] over the editor in [child].
  const CrdtQuillCursorsOverlay({
    required this.id,
    required this.cursors,
    required this.child,
    this.labelPlacement = CrdtTextCursorLabelPlacement.auto,
    this.motionDuration = CrdtTextCursorsOverlay.defaultMotionDuration,
    super.key,
  });

  /// See [CrdtTextCursorsOverlay.id].
  final String id;

  /// See [CrdtTextCursorsOverlay.cursors].
  final List<CrdtTextCursor> cursors;

  /// See [CrdtTextCursorsOverlay.labelPlacement].
  final CrdtTextCursorLabelPlacement labelPlacement;

  /// See [CrdtTextCursorsOverlay.motionDuration].
  final Duration motionDuration;

  /// The subtree containing the `QuillEditor` to draw over.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CrdtTextCursorsOverlay(
      id: id,
      cursors: cursors,
      labelPlacement: labelPlacement,
      motionDuration: motionDuration,
      targetOf: _quillTarget,
      child: child,
    );
  }
}

CrdtTextCursorsTarget? _quillTarget(RenderObject node) =>
    node is RenderEditor ? _RenderEditorTarget(node) : null;

class _RenderEditorTarget implements CrdtTextCursorsTarget {
  const _RenderEditorTarget(this._editor);

  final RenderEditor _editor;

  @override
  bool get attached => _editor.attached;

  // The document on screen: an empty one shows the placeholder's.
  @override
  String get text => _editor.document.toPlainText();

  // The scroll view around the editor moves it, so the transform has it.
  @override
  Offset get scroll => Offset.zero;

  @override
  Rect caretRect(int offset) {
    // Past Quill's last newline there is no line to ask.
    final position = TextPosition(
      offset: math.min(offset, _editor.document.length - 1),
    );
    final rect = _editor.getLocalRectForCaret(position);
    // That rect leaves out the horizontal padding of the editor.
    final point = _editor
        .getEndpointsForSelection(TextSelection.fromPosition(position))
        .first
        .point;
    return rect.translate(point.dx - rect.left, 0);
  }

  // The editor gives no boxes: walk the visual lines.
  @override
  List<Rect> selectionRects(TextSelection range) {
    final text = this.text;
    final rects = <Rect>[];
    var at = range.start;
    while (at < range.end) {
      // Past the end of a line, or an empty one, which has no line boundary.
      if (text[at] == '\n') {
        at++;
        continue;
      }
      final line = _editor.getLineAtOffset(TextPosition(offset: at));
      final points = _editor.getEndpointsForSelection(
        TextSelection(
          baseOffset: at,
          extentOffset: math.min(line.end, range.end),
        ),
      );
      final top = _editor.getLocalRectForCaret(TextPosition(offset: at)).top;
      final first = points.first.point;
      final last = points.last.point;
      rects.add(
        Rect.fromLTRB(
          math.min(first.dx, last.dx),
          top,
          math.max(first.dx, last.dx),
          last.dy,
        ),
      );
      at = math.max(line.end, at + 1);
    }
    return rects;
  }

  @override
  Matrix4 getTransformTo(RenderObject ancestor) =>
      _editor.getTransformTo(ancestor);
}
