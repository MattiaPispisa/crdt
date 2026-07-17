import 'dart:async';
import 'dart:math' as math;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/crdt_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// {@template crdt_text_cursor}
/// A collaborator's text cursor to draw over a text field: identity, paint
/// style and the stable anchors of their selection.
///
/// The anchors come from `CRDTFugueTextHandler.stablePositionAt` on the
/// collaborator's side (see `CrdtTextFieldBuilder.onSelectionAnchorsChanged`)
/// and typically travel over an ephemeral presence channel — they must NOT
/// be part of the document history.
/// {@endtemplate}
@immutable
class CrdtTextCursor {
  /// {@macro crdt_text_cursor}
  ///
  /// Creates a text cursor. [extent] defaults to [base] (a collapsed
  /// caret).
  const CrdtTextCursor({
    required this.id,
    required this.color,
    required this.base,
    FugueElementID? extent,
    this.label,
  }) : extent = extent ?? base;

  /// Identity of the collaborator (used only for equality).
  final Object id;

  /// Caret and selection-highlight color.
  final Color color;

  /// Small name tag drawn above the caret; omitted when `null`.
  final String? label;

  /// Stable anchor of the selection base.
  final FugueElementID base;

  /// Stable anchor of the selection extent; equal to [base] for a caret.
  final FugueElementID extent;

  @override
  bool operator ==(Object other) =>
      other is CrdtTextCursor &&
      other.id == id &&
      other.color == color &&
      other.label == label &&
      other.base == base &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(id, color, label, base, extent);
}

/// Where [CrdtTextCursorsOverlay] draws a cursor's name tag, relative to
/// the caret.
enum CrdtTextCursorLabelPlacement {
  /// Above the caret; flips below it when the tag would escape the field's
  /// top edge. The default.
  auto,

  /// Always above the caret.
  above,

  /// Always below the caret.
  below,
}

/// The rect of a cursor name tag of [labelSize], anchored to [caret] inside
/// a field of [bounds], following [placement].
///
/// Clamped horizontally into [bounds]; with
/// [CrdtTextCursorLabelPlacement.auto] it sits above the caret and flips
/// below it when the top edge would be crossed.
@visibleForTesting
Rect resolveTextCursorLabelRect({
  required Size labelSize,
  required Rect caret,
  required Size bounds,
  required CrdtTextCursorLabelPlacement placement,
}) {
  const gap = 4.0;
  final left = math
      .max(0, math.min(caret.left, bounds.width - labelSize.width))
      .toDouble();
  final above = caret.top - labelSize.height - gap;
  final below = caret.bottom + gap;
  final top = switch (placement) {
    CrdtTextCursorLabelPlacement.above => above,
    CrdtTextCursorLabelPlacement.below => below,
    CrdtTextCursorLabelPlacement.auto => above >= 0 ? above : below,
  };
  return Rect.fromLTWH(left, top, labelSize.width, labelSize.height);
}

/// {@template crdt_text_cursors_overlay}
/// Paints the carets and selections of remote collaborators over [child]
/// (the subtree containing the `TextField` bound to the same handler [id]).
///
/// Each [CrdtTextCursor] is anchored by stable positions
/// (`stablePositionAt`), so an anchor received once stays correct forever.
///
/// Like `CrdtTextFieldBuilder`, it never rebuilds its subtree: document
/// updates and scrolls only schedule a repaint of the painter.
///
/// Cursors are painted into the app [Overlay] (via [OverlayPortal]), so
/// sibling widgets painted after the field — a following container's
/// border, the next card — can never cover a caret or its name tag.
/// Requires an [Overlay] ancestor (`MaterialApp`/[WidgetsApp] provide one).
///
/// Requires a `CRDTFugueTextHandler` under [id]: only Fugue handlers carry
/// the element identity that anchors are made of.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => CrdtTextCursorsOverlay(
///     id: 'note',
///     cursors: cursors, // from your presence channel
///     child: TextField(controller: controller),
///   ),
/// ),
/// ```
/// {@endtemplate}
class CrdtTextCursorsOverlay extends StatefulWidget {
  /// {@macro crdt_text_cursors_overlay}
  ///
  /// Create a CrdtTextCursorsOverlay.
  const CrdtTextCursorsOverlay({
    required this.id,
    required this.cursors,
    required this.child,
    this.labelPlacement = CrdtTextCursorLabelPlacement.auto,
    super.key,
  });

  /// The id of the text handler the cursors refer to.
  /// **must be a [CRDTFugueTextHandler]**
  final String id;

  /// The text cursors to draw.
  final List<CrdtTextCursor> cursors;

  /// Where the name tags sit relative to the caret; see
  /// [CrdtTextCursorLabelPlacement]. Defaults to
  /// [CrdtTextCursorLabelPlacement.auto].
  final CrdtTextCursorLabelPlacement labelPlacement;

  /// The subtree containing the text field to draw over.
  final Widget child;

  @override
  State<CrdtTextCursorsOverlay> createState() => _CrdtTextCursorsOverlayState();
}

class _CrdtTextCursorsOverlayState extends State<CrdtTextCursorsOverlay> {
  CRDTDocument? _document;
  StreamSubscription<void>? _subscription;
  int _lastRevision = 0;
  final _repaint = _RepaintNotifier();

  /// Anchors the [OverlayPortal] paint surface to this widget's origin, so
  /// the painter keeps working in field-local coordinates while living in
  /// the app [Overlay] (above everything a sibling could paint).
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  /// Cached [RenderEditable] found under this widget; re-resolved when the
  /// child subtree changes.
  RenderEditable? _editable;

  @override
  void initState() {
    super.initState();
    // Safe while detached: the controller records the pending z-order and
    // the portal shows on attach.
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final document = context.crdtDocument;
    if (!identical(document, _document)) {
      _attach(document);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        // The field scrolled: rects moved, repaint (never rebuild).
        _repaint.bump();
        return false;
      },
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => IgnorePointer(
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              child: CustomPaint(painter: _TextCursorsPainter(this)),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(CrdtTextCursorsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.cursors, widget.cursors) ||
        oldWidget.labelPlacement != widget.labelPlacement) {
      _repaint.bump();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  void _attach(CRDTDocument document) {
    _subscription?.cancel();
    _document = document;
    _lastRevision = document.revisionForHandler(widget.id);
    _handler(); // fail fast on a wrong handler type
    _subscription = document.updates.listen((_) {
      final revision = document.revisionForHandler(widget.id);
      if (revision == _lastRevision) {
        return;
      }
      _lastRevision = revision;
      // The text changed: the anchors resolve to new indices, repaint.
      _repaint.bump();
    });
  }

  CRDTFugueTextHandler _handler() {
    final handler = _document!.registeredHandlers[widget.id];
    if (handler is CRDTFugueTextHandler) {
      return handler;
    }
    throw FlutterError(
      'CrdtTextCursorsOverlay expected a CRDTFugueTextHandler registered '
      'under id "${widget.id}" (stable cursor anchors need Fugue element '
      'identity), but found ${handler ?? 'none'}.',
    );
  }

  /// The [RenderEditable] of the text field inside
  /// [CrdtTextCursorsOverlay.child].
  RenderEditable? _findEditable() {
    if (_editable != null && _editable!.attached) {
      return _editable;
    }
    _editable = null;
    void visit(RenderObject node) {
      if (_editable != null) {
        return;
      }
      if (node is RenderEditable) {
        _editable = node;
        return;
      }
      node.visitChildren(visit);
    }

    final root = context.findRenderObject();
    root?.visitChildren(visit);
    return _editable;
  }
}

class _RepaintNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _TextCursorsPainter extends CustomPainter {
  _TextCursorsPainter(this._state) : super(repaint: _state._repaint);

  final _CrdtTextCursorsOverlayState _state;

  static const _caretWidth = 2.0;

  /// Name-tag pill geometry, matching the mouse-style presence cursors.
  static const _labelHeight = 18.0;
  static const _labelMaxWidth = 140.0;
  static const _labelPadding = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final editable = _state._findEditable();
    if (editable == null || !editable.attached) {
      return;
    }
    // The paint surface lives in the app Overlay, anchored to the widget's
    // origin: coordinates and bounds come from the widget's own render box,
    // not from [size].
    final overlayBox = _state.context.findRenderObject();
    if (overlayBox is! RenderBox || !overlayBox.hasSize) {
      return;
    }
    final fieldSize = overlayBox.size;
    final handler = _state._handler();
    final transform = editable.getTransformTo(overlayBox);
    final bounds = Offset.zero & fieldSize;
    final labels = <(CrdtTextCursor, Rect)>[];

    // Carets and selections follow the field's inner scroll: keep them
    // clipped to the overlay. Labels are painted after, without clipping.
    canvas
      ..save()
      ..clipRect(bounds);

    for (final cursor in _state.widget.cursors) {
      final base = handler.indexOfStablePosition(cursor.base);
      final extent = cursor.extent == cursor.base
          ? base
          : handler.indexOfStablePosition(cursor.extent);
      if (extent == null) {
        // The anchored element is not known yet: hide until it arrives.
        continue;
      }

      if (base != null && base != extent) {
        final highlight = Paint()..color = cursor.color.withValues(alpha: .3);
        final selection = TextSelection(
          baseOffset: math.min(base, extent),
          extentOffset: math.max(base, extent),
        );
        for (final box in editable.getBoxesForSelection(selection)) {
          canvas.drawRect(
            MatrixUtils.transformRect(transform, box.toRect()),
            highlight,
          );
        }
      }

      final caret = MatrixUtils.transformRect(
        transform,
        editable.getLocalRectForCaret(TextPosition(offset: extent)),
      );
      canvas.drawRect(
        Rect.fromLTWH(caret.left, caret.top, _caretWidth, caret.height),
        Paint()..color = cursor.color,
      );

      // A label only makes sense next to a visible caret (a caret scrolled
      // out of view must not leave a floating tag around).
      if (cursor.label != null && bounds.overlaps(caret)) {
        labels.add((cursor, caret));
      }
    }

    canvas.restore();
    for (final (cursor, caret) in labels) {
      _paintLabel(canvas, cursor, caret, fieldSize);
    }
  }

  /// A pill-shaped name tag next to the caret (the same look as the
  /// mouse-style presence cursor bubbles), never clipped by the field:
  /// placed per [CrdtTextCursorsOverlay.labelPlacement] and clamped
  /// horizontally. Long names are truncated with an ellipsis at
  /// [_labelMaxWidth].
  void _paintLabel(
    Canvas canvas,
    CrdtTextCursor cursor,
    Rect caret,
    Size size,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: cursor.label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _labelMaxWidth - _labelPadding * 2);
    final tag = resolveTextCursorLabelRect(
      labelSize: Size(text.width + _labelPadding * 2, _labelHeight),
      caret: caret,
      bounds: size,
      placement: _state.widget.labelPlacement,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tag, const Radius.circular(_labelHeight / 2)),
      Paint()..color = cursor.color,
    );
    text.paint(
      canvas,
      tag.topLeft + Offset(_labelPadding, (_labelHeight - text.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_TextCursorsPainter oldDelegate) =>
      oldDelegate._state != _state;
}
