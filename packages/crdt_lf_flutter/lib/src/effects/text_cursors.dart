import 'dart:async';
import 'dart:math' as math;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
/// Like `CrdtTextFieldBuilder`, it never rebuilds its subtree: a scroll only
/// repaints the painter, and a document update at most re-measures where the
/// anchors landed.
///
/// A caret glides to its new position over [motionDuration] instead of
/// jumping there, so a collaborator typing over the network reads as one
/// continuous movement.
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
    this.motionDuration = const Duration(milliseconds: 120),
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

  /// How long a caret (and its name tag) takes to glide to a new position.
  ///
  /// Movement is smoothed in the text's own coordinates: scrolling the field
  /// carries the carets along instantly, only movement through the text is
  /// animated.
  ///
  /// A caret that lands far away — several lines up or down, or a good part
  /// of the field away on the same line — snaps rather than sweep across the
  /// field.
  ///
  /// Defaults to 120ms; [Duration.zero] paints every move instantly.
  final Duration motionDuration;

  /// The subtree containing the text field to draw over.
  final Widget child;

  @override
  State<CrdtTextCursorsOverlay> createState() => _CrdtTextCursorsOverlayState();
}

class _CrdtTextCursorsOverlayState extends State<CrdtTextCursorsOverlay>
    with SingleTickerProviderStateMixin {
  CRDTDocument? _document;
  StreamSubscription<void>? _subscription;
  int _lastRevision = 0;
  final _repaint = _RepaintNotifier();

  /// The gliding carets, keyed by [CrdtTextCursor.id].
  /// One [Ticker] drives them all.
  final _motions = <Object, _CaretMotion>{};
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// What the painter draws: the cursors resolved against the current text,
  /// rebuilt by [_resolve] whenever the document, the cursors or the layout
  /// change — never on a frame that only advances a glide.
  List<_ResolvedCursor> _resolved = const [];

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
    _ticker = createTicker(_onTick);
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
    return _ResolveTargets(
      onResolve: _resolve,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          // The field scrolled: the carets keep their place in the text and
          // only the paint offset moved, repaint (never rebuild).
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
      ),
    );
  }

  @override
  void didUpdateWidget(CrdtTextCursorsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.cursors, widget.cursors) ||
        oldWidget.motionDuration != widget.motionDuration) {
      _invalidate();
    } else if (oldWidget.labelPlacement != widget.labelPlacement) {
      // Only the tags moved: the anchors resolve where they already did.
      _repaint.bump();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Resolves every cursor against the current text and sends the carets on
  /// their way; the painter then only draws what is left here.
  ///
  /// Runs as the field of [size] starts painting ([_ResolveTargets]), so the
  /// text metrics it reads are the ones of this very frame and the carets,
  /// painted later into the [Overlay], are never a frame behind.
  ///
  /// Only invalidations get here — a frame that merely advances a glide
  /// repaints the carets without touching the document.
  void _resolve(Size size) {
    final editable = _findEditable();
    if (editable == null) {
      _resolved = const [];
      return;
    }
    final handler = _handler();
    final scroll = _editableScroll(editable);
    final animate = widget.motionDuration > Duration.zero;
    final resolved = <_ResolvedCursor>[];
    final live = <Object>{};
    var gliding = false;

    for (final cursor in widget.cursors) {
      final base = handler.indexOfStablePosition(cursor.base);
      final extent = cursor.extent == cursor.base
          ? base
          : handler.indexOfStablePosition(cursor.extent);
      if (extent == null) {
        // The anchored element is not known yet: hide until it arrives.
        continue;
      }

      final selection = <Rect>[];
      if (base != null && base != extent) {
        final range = TextSelection(
          baseOffset: math.min(base, extent),
          extentOffset: math.max(base, extent),
        );
        for (final box in editable.getBoxesForSelection(range)) {
          selection.add(box.toRect().shift(-scroll));
        }
      }

      final target = editable
          .getLocalRectForCaret(TextPosition(offset: extent))
          .shift(-scroll);
      live.add(cursor.id);
      final motion = _motions[cursor.id];
      if (motion == null) {
        // First sight (or a cursor back from an unknown anchor): appear
        // where it belongs instead of flying in from a stale position.
        _motions[cursor.id] = _CaretMotion(target);
      } else {
        gliding |= motion.retarget(target, animate: animate, width: size.width);
      }
      resolved.add(_ResolvedCursor(cursor, _motions[cursor.id]!, selection));
    }

    // A cursor that went away (removed, or its anchor unknown again) forgets
    // where it was, so it reappears in place rather than gliding from there.
    _motions.removeWhere((id, _) => !live.contains(id));
    _resolved = resolved;
    if (gliding) {
      _startTicking();
    }
  }

  /// Marks the resolved cursors stale: the next frame re-measures where the
  /// anchors landed and paints the carets with the result.
  ///
  /// The two marks belong together — [_resolve] runs inside the paint phase,
  /// where it can no longer ask the painter for a repaint of its own.
  void _invalidate() {
    context.findRenderObject()?.markNeedsPaint();
    _repaint.bump();
  }

  /// Starts the glide clock if a caret is on its way somewhere.
  ///
  /// Called from within a frame, so the [Ticker] takes it as its start time
  /// and the very next frame already moves the caret.
  void _startTicking() {
    if (_ticker.isActive) {
      return;
    }
    _lastTick = Duration.zero;
    _ticker.start();
  }

  bool get _settled => _motions.values.every((motion) => motion.settled);

  /// Moves every caret a slice of the way to its target and repaints.
  ///
  /// The step is an exponential settle (~98% of the distance covered in
  /// [CrdtTextCursorsOverlay.motionDuration]): frame-rate independent, and
  /// stable when the target moves mid-glide. A long gap between ticks — a
  /// muted [Ticker] on an off-screen field — resolves to a snap.
  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final tau = widget.motionDuration.inMicroseconds /
        (4 * Duration.microsecondsPerSecond);
    final t = tau <= 0 ? 1.0 : 1 - math.exp(-dt / tau);
    for (final motion in _motions.values) {
      motion.advance(t);
    }
    if (_settled) {
      _ticker.stop();
    }
    _repaint.bump();
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
      // The text changed: the anchors resolve to new indices, resolve again.
      _invalidate();
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

/// The field's own scroll, as [RenderEditable] bakes it into every rect it
/// hands out: a horizontal viewport on a single line, vertical otherwise.
///
/// Taking it out gives the text's own coordinates, where a caret only moves
/// when it moves through the text.
Offset _editableScroll(RenderEditable editable) {
  if (!editable.offset.hasPixels) {
    return Offset.zero;
  }
  final pixels = editable.offset.pixels;
  return editable.maxLines == 1 ? Offset(-pixels, 0) : Offset(0, -pixels);
}

/// Calls [onResolve] as it starts painting the field, with the size it was
/// laid out to.
///
/// That is the one moment where the text metrics are both settled (layout is
/// over) and readable ([RenderBox.size] is off limits during layout), and it
/// comes before the app [Overlay] — hence before the carets — is painted.
class _ResolveTargets extends SingleChildRenderObjectWidget {
  const _ResolveTargets({required this.onResolve, required super.child});

  final ValueSetter<Size> onResolve;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderResolveTargets(onResolve);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderResolveTargets renderObject,
  ) {
    renderObject.onResolve = onResolve;
  }
}

class _RenderResolveTargets extends RenderProxyBox {
  _RenderResolveTargets(this.onResolve);

  /// Called at the start of every paint, with the size laid out.
  ValueSetter<Size> onResolve;

  @override
  void paint(PaintingContext context, Offset offset) {
    onResolve(size);
    super.paint(context, offset);
  }
}

/// A cursor resolved against the current text: its gliding caret and the
/// boxes of its selection, in the text's own (unscrolled) coordinates.
class _ResolvedCursor {
  const _ResolvedCursor(this.cursor, this.motion, this.selection);

  final CrdtTextCursor cursor;
  final _CaretMotion motion;
  final List<Rect> selection;
}

/// A caret on its way from where it is painted ([shown]) to where the
/// anchor now resolves ([target]), both in the text's own (unscrolled)
/// coordinates.
class _CaretMotion {
  _CaretMotion(Rect at)
      : shown = at,
        target = at;

  /// The rect currently painted.
  Rect shown;

  /// The rect [shown] is heading to.
  Rect target;

  /// Whether landing on [rect] is a jump rather than a move: a collaborator
  /// clicking elsewhere or pasting a block must not sweep across the field.
  static bool isJump(Rect from, Rect rect, double width) =>
      (rect.center.dy - from.center.dy).abs() > 2 * rect.height ||
      (rect.center.dx - from.center.dx).abs() > width / 3;

  bool get settled => shown == target;

  /// Sends this caret to [rect], gliding unless the move is a [isJump] in a
  /// field [width] wide.
  ///
  /// Returns whether a glide is now in flight.
  bool retarget(Rect rect, {required bool animate, required double width}) {
    target = rect;
    if (!animate || isJump(shown, rect, width)) {
      shown = rect;
    }
    return !settled;
  }

  /// Covers a fraction [t] of the remaining distance, snapping when the
  /// leftover is under half a pixel (an invisible difference that would
  /// otherwise keep the clock running forever).
  void advance(double t) {
    if (settled) {
      return;
    }
    final next = Rect.lerp(shown, target, t)!;
    const epsilon = 0.5;
    shown = (next.left - target.left).abs() < epsilon &&
            (next.top - target.top).abs() < epsilon &&
            (next.right - target.right).abs() < epsilon &&
            (next.bottom - target.bottom).abs() < epsilon
        ? target
        : next;
  }
}

class _TextCursorsPainter extends CustomPainter {
  _TextCursorsPainter(this._state) : super(repaint: _state._repaint);

  final _CrdtTextCursorsOverlayState _state;

  static const _caretWidth = 2.0;

  /// Name-tag pill geometry, matching the mouse-style presence cursors.
  static const _labelHeight = 18.0;
  static const _labelMaxWidth = 140.0;
  static const _labelPadding = 8.0;

  /// Draws what [_CrdtTextCursorsOverlayState._resolve] left, putting the
  /// field's scroll back on top of the text coordinates it works in.
  ///
  /// Reads only: nothing here resolves anchors or advances a glide, so the
  /// frames that merely carry a caret along cost a repaint and no more.
  @override
  void paint(Canvas canvas, Size size) {
    final editable = _state._editable;
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
    final transform = editable.getTransformTo(overlayBox);
    final scroll = _editableScroll(editable);
    final bounds = Offset.zero & fieldSize;
    final labels = <(CrdtTextCursor, Rect)>[];

    // Carets and selections follow the field's inner scroll: keep them
    // clipped to the overlay. Labels are painted after, without clipping.
    canvas
      ..save()
      ..clipRect(bounds);

    // Handler indices count runes; `RenderEditable` indexes code units.
    final text = handler.value;

    for (final cursor in _state.widget.cursors) {
      final baseIndex = handler.indexOfStablePosition(cursor.base);
      final extentIndex = cursor.extent == cursor.base
          ? baseIndex
          : handler.indexOfStablePosition(cursor.extent);
      if (extentIndex == null) {
        // The anchored element is not known yet: hide until it arrives.
        continue;
      }

      final extent = RuneOffsets.utf16Offset(text, extentIndex);
      final base =
          baseIndex == null ? null : RuneOffsets.utf16Offset(text, baseIndex);

      if (base != null && base != extent) {
        final highlight = Paint()..color = cursor.color.withValues(alpha: .3);
        for (final box in resolved.selection) {
          canvas.drawRect(
            MatrixUtils.transformRect(transform, box.shift(scroll)),
            highlight,
          );
        }
      }

      final caret = MatrixUtils.transformRect(
        transform,
        resolved.motion.shown.shift(scroll),
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
