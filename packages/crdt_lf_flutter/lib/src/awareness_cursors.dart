import 'package:crdt_lf_flutter/src/text_cursors.dart';
import 'package:flutter/widgets.dart';

/// {@template crdt_awareness_cursor}
/// A collaborator's pointer (a mouse-style presence cursor) to draw over a
/// pane: identity, paint style and the pointer position normalized into
/// `[0, 1]` — so cursors map correctly across windows of different sizes.
///
/// Presence state is ephemeral: it typically travels over a presence
/// channel (e.g. the awareness plugin of `crdt_socket_sync`) and must NOT
/// be part of the document history.
///
/// Not to be confused with [CrdtTextCursor], the caret a collaborator has
/// **inside a text field**, anchored to CRDT element identity.
/// {@endtemplate}
@immutable
class CrdtAwarenessCursor {
  /// {@macro crdt_awareness_cursor}
  const CrdtAwarenessCursor({
    required this.id,
    required this.color,
    required this.position,
    this.label,
    this.hovering = false,
  });

  /// Identity of the collaborator (used for equality and marker identity).
  final Object id;

  /// Pointer arrow and name-bubble color.
  final Color color;

  /// Name bubble drawn under the pointer; omitted when `null`.
  final String? label;

  /// Pointer position, normalized into `[0, 1]` on both axes.
  final Offset position;

  /// Whether the collaborator's pointer is currently over the pane; the
  /// pointer arrow is drawn slightly larger while hovering.
  final bool hovering;

  @override
  bool operator ==(Object other) =>
      other is CrdtAwarenessCursor &&
      other.id == id &&
      other.color == color &&
      other.label == label &&
      other.position == position &&
      other.hovering == hovering;

  @override
  int get hashCode => Object.hash(id, color, label, position, hovering);
}

/// Reports the local pointer, normalized into `[0, 1]`; `hovering` is false
/// when the pointer left the pane.
typedef CrdtLocalPointerCallback = void Function(
  Offset position, {
  required bool hovering,
});

/// {@template crdt_awareness_cursors_overlay}
/// Overlays the mouse-style presence cursors of remote collaborators on top
/// of [child], and reports the local pointer through [onLocalPointer] so
/// the app can publish it on its presence channel.
///
/// Transport-agnostic: the widget only renders [cursors] — mapping presence
/// state (e.g. the awareness plugin of `crdt_socket_sync`) to
/// [CrdtAwarenessCursor]s and publishing what [onLocalPointer] reports is
/// the app's bridge code.
///
/// ## Example
/// ```dart
/// CrdtAwarenessCursorsOverlay(
///   cursors: remotePointers, // List<CrdtAwarenessCursor> from presence
///   onLocalPointer: (position, {required hovering}) =>
///       publishPresence(position, hovering),
///   child: pane,
/// ),
/// ```
/// {@endtemplate}
class CrdtAwarenessCursorsOverlay extends StatelessWidget {
  /// {@macro crdt_awareness_cursors_overlay}
  const CrdtAwarenessCursorsOverlay({
    required this.cursors,
    required this.child,
    this.onLocalPointer,
    super.key,
  });

  /// The remote pointers to draw.
  final List<CrdtAwarenessCursor> cursors;

  /// Called with the local pointer position (normalized into `[0, 1]`) on
  /// hover, and with `hovering: false` when the pointer leaves the pane.
  final CrdtLocalPointerCallback? onLocalPointer;

  /// The wrapped pane content.
  final Widget child;

  void _report(Size size, Offset local, {required bool hovering}) {
    if (size.isEmpty) {
      return;
    }
    onLocalPointer?.call(
      Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      ),
      hovering: hovering,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          opaque: false,
          onHover: (event) =>
              _report(size, event.localPosition, hovering: true),
          onExit: (event) =>
              _report(size, event.localPosition, hovering: false),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      for (final cursor in cursors)
                        AnimatedPositioned(
                          key: ValueKey(cursor.id),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          left: cursor.position.dx * size.width,
                          top: cursor.position.dy * size.height,
                          child: _CursorMarker(cursor: cursor),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Name-bubble pill geometry, identical to the name tags painted by
/// [CrdtTextCursorsOverlay] — the two presence layers share one look.
const double _kMaxBubbleWidth = 140;
const double _kBubbleHeight = 18;
const double _kBubblePadding = 8;

/// Pointer arrow geometry: the Figma-style kite fits this square, tip at
/// its top-left. The name bubble hangs at the pointer's bottom-right with
/// a small gap, so arrow and bubble read as two elements, not one blob.
const double _kPointerSize = 18;
const Offset _kBubbleOffset = Offset(12, 3);

/// A Figma-style pointer arrow plus a name bubble bounded to
/// [_kMaxBubbleWidth]; long names are truncated with an ellipsis.
class _CursorMarker extends StatelessWidget {
  const _CursorMarker({required this.cursor});

  final CrdtAwarenessCursor cursor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pointer tip at the widget's top-left ~ the actual position.
        // Grows smoothly while the collaborator is hovering.
        AnimatedScale(
          scale: cursor.hovering ? 1.25 : 1,
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.topLeft,
          child: CustomPaint(
            size: const Size(_kPointerSize, _kPointerSize),
            painter: _PointerPainter(color: cursor.color),
          ),
        ),
        // Name bubble: fixed height, capped width, long names truncated.
        if (cursor.label != null)
          Padding(
            padding: EdgeInsets.only(
              left: _kBubbleOffset.dx,
              top: _kBubbleOffset.dy,
            ),
            child: Container(
              height: _kBubbleHeight,
              constraints: const BoxConstraints(maxWidth: _kMaxBubbleWidth),
              padding: const EdgeInsets.symmetric(horizontal: _kBubblePadding),
              decoration: BoxDecoration(
                color: cursor.color,
                borderRadius: BorderRadius.circular(_kBubbleHeight / 2),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                cursor.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A kite-shaped arrow with its tip at the
/// top-left corner, filled with the peer color, outlined in white (so it
/// stays visible on any background) over a soft shadow.
class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 1)
      ..lineTo(size.width - 2, size.height * 0.38)
      ..lineTo(size.width * 0.53, size.height * 0.53)
      ..lineTo(size.width * 0.38, size.height - 2)
      ..close();
    canvas
      ..drawShadow(path, const Color(0x66000000), 2, true)
      ..drawPath(path, Paint()..color = color)
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => oldDelegate.color != color;
}
