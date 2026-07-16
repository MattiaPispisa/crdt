import 'dart:async';
import 'dart:math' as math;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/crdt_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// {@template crdt_remote_cursor}
/// A collaborator's cursor to draw over a text field: identity, paint style
/// and the stable anchors of their selection.
///
/// The anchors come from `CRDTFugueTextHandler.stablePositionAt` on the
/// collaborator's side (see `CrdtTextFieldBuilder.onSelectionAnchorsChanged`)
/// and typically travel over an ephemeral presence channel — they must NOT
/// be part of the document history.
/// {@endtemplate}
@immutable
class CrdtRemoteCursor {
  /// {@macro crdt_remote_cursor}
  ///
  /// Creates a remote cursor. [extent] defaults to [base] (a collapsed
  /// caret).
  const CrdtRemoteCursor({
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
      other is CrdtRemoteCursor &&
      other.id == id &&
      other.color == color &&
      other.label == label &&
      other.base == base &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(id, color, label, base, extent);
}

/// Where [CrdtRemoteCursorsOverlay] draws a cursor's name tag, relative to
/// the caret.
enum CrdtCursorLabelPlacement {
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
/// [CrdtCursorLabelPlacement.auto] it sits above the caret and flips below
/// it when the top edge would be crossed.
@visibleForTesting
Rect resolveCursorLabelRect({
  required Size labelSize,
  required Rect caret,
  required Size bounds,
  required CrdtCursorLabelPlacement placement,
}) {
  const gap = 4.0;
  final left = math
      .max(0, math.min(caret.left, bounds.width - labelSize.width))
      .toDouble();
  final above = caret.top - labelSize.height - gap;
  final below = caret.bottom + gap;
  final top = switch (placement) {
    CrdtCursorLabelPlacement.above => above,
    CrdtCursorLabelPlacement.below => below,
    CrdtCursorLabelPlacement.auto => above >= 0 ? above : below,
  };
  return Rect.fromLTWH(left, top, labelSize.width, labelSize.height);
}

/// {@template crdt_remote_cursors_overlay}
/// Paints the carets and selections of remote collaborators over [child]
/// (the subtree containing the `TextField` bound to the same handler [id]).
///
/// Each [CrdtRemoteCursor] is anchored by stable positions
/// (`stablePositionAt`), so an anchor received once stays correct forever.
///
/// Like `CrdtTextFieldBuilder`, it never rebuilds its subtree: document
/// updates and scrolls only schedule a repaint of the painter.
///
/// Requires a `CRDTFugueTextHandler` under [id]: only Fugue handlers carry
/// the element identity that anchors are made of.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => CrdtRemoteCursorsOverlay(
///     id: 'note',
///     cursors: cursors, // from your presence channel
///     child: TextField(controller: controller),
///   ),
/// ),
/// ```
/// {@endtemplate}
class CrdtRemoteCursorsOverlay extends StatefulWidget {
  /// {@macro crdt_remote_cursors_overlay}
  ///
  /// Create a CrdtRemoteCursorsOverlay.
  const CrdtRemoteCursorsOverlay({
    required this.id,
    required this.cursors,
    required this.child,
    this.labelPlacement = CrdtCursorLabelPlacement.auto,
    super.key,
  });

  /// The id of the text handler the cursors refer to.
  /// **must be a [CRDTFugueTextHandler]**
  final String id;

  /// The remote cursors to draw.
  final List<CrdtRemoteCursor> cursors;

  /// Where the name tags sit relative to the caret; see
  /// [CrdtCursorLabelPlacement]. Defaults to
  /// [CrdtCursorLabelPlacement.auto].
  final CrdtCursorLabelPlacement labelPlacement;

  /// The subtree containing the text field to draw over.
  final Widget child;

  @override
  State<CrdtRemoteCursorsOverlay> createState() =>
      _CrdtRemoteCursorsOverlayState();
}

class _CrdtRemoteCursorsOverlayState extends State<CrdtRemoteCursorsOverlay> {
  CRDTDocument? _document;
  StreamSubscription<void>? _subscription;
  int _lastRevision = 0;
  final _repaint = _RepaintNotifier();

  /// Cached [RenderEditable] found under this widget; re-resolved when the
  /// child subtree changes.
  RenderEditable? _editable;

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
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _RemoteCursorsPainter(this)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(CrdtRemoteCursorsOverlay oldWidget) {
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
      'CrdtRemoteCursorsOverlay expected a CRDTFugueTextHandler registered '
      'under id "${widget.id}" (stable cursor anchors need Fugue element '
      'identity), but found ${handler ?? 'none'}.',
    );
  }

  /// The [RenderEditable] of the text field inside
  /// [CrdtRemoteCursorsOverlay.child].
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

class _RemoteCursorsPainter extends CustomPainter {
  _RemoteCursorsPainter(this._state) : super(repaint: _state._repaint);

  final _CrdtRemoteCursorsOverlayState _state;

  static const _caretWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final editable = _state._findEditable();
    if (editable == null || !editable.attached) {
      return;
    }
    final overlayBox = _state.context.findRenderObject();
    if (overlayBox == null) {
      return;
    }
    final handler = _state._handler();
    final transform = editable.getTransformTo(overlayBox);
    final bounds = Offset.zero & size;
    final labels = <(CrdtRemoteCursor, Rect)>[];

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
      _paintLabel(canvas, cursor, caret, size);
    }
  }

  /// A small name tag next to the caret, never clipped by the field: placed
  /// per [CrdtRemoteCursorsOverlay.labelPlacement] and clamped horizontally.
  void _paintLabel(
    Canvas canvas,
    CrdtRemoteCursor cursor,
    Rect caret,
    Size size,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: cursor.label,
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tag = resolveCursorLabelRect(
      labelSize: Size(text.width + 8, text.height + 4),
      caret: caret,
      bounds: size,
      placement: _state.widget.labelPlacement,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tag, const Radius.circular(3)),
      Paint()..color = cursor.color,
    );
    text.paint(canvas, tag.topLeft + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(_RemoteCursorsPainter oldDelegate) =>
      oldDelegate._state != _state;
}
