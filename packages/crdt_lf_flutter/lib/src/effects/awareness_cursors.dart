import 'package:crdt_lf_flutter/src/effects/text_cursors.dart';
import 'package:flutter/widgets.dart';

/// {@template crdt_awareness_cursor}
/// A collaborator's pointer (a mouse-style presence cursor) to draw over a
/// pane: identity, paint color, the pointer position normalized into
/// `[0, 1]` (so cursors map correctly across windows of different sizes) and
/// an optional per-cursor [style].
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
    this.style,
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

  /// Per-cursor look (name text style, marker sizes). When `null`, the
  /// ambient style (e.g. [CrdtAwarenessCursorsOverlay.style]) or the default
  /// is used. The style's own color is ignored: this cursor's [color] above
  /// always wins, keeping the peer's identity color.
  final CrdtAwarenessCursorStyle? style;

  @override
  bool operator ==(Object other) =>
      other is CrdtAwarenessCursor &&
      other.id == id &&
      other.color == color &&
      other.label == label &&
      other.position == position &&
      other.hovering == hovering &&
      other.style == style;

  @override
  int get hashCode => Object.hash(id, color, label, position, hovering, style);
}

/// Reports the local pointer, normalized into `[0, 1]`; `hovering` is false
/// when the pointer left the pane.
typedef CrdtLocalPointerCallback = void Function(
  Offset position, {
  required bool hovering,
});

/// Builds the widget drawn at a remote collaborator's pointer, given its
/// presence [cursor]. Used by [CrdtAwarenessCursorsBuilder]; the returned
/// widget is positioned with its top-left at the pointer.
typedef CrdtAwarenessCursorWidgetBuilder = Widget Function(
  BuildContext context,
  CrdtAwarenessCursor cursor,
);

/// {@template crdt_awareness_cursors_builder}
/// The transport/layout half of the presence overlay: it lays remote
/// pointers over [child] (positioning each at its normalized
/// [CrdtAwarenessCursor.position]) and reports the local pointer through
/// [onLocalPointer], but delegates the look of every cursor to [builder].
///
/// Use this when you want the positioning and local-pointer handling of
/// [CrdtAwarenessCursorsOverlay] but full control over what a cursor looks
/// like — return any widget from [builder] (a styled
/// [CrdtAwarenessCursorMarker], an avatar, a custom painter). For the
/// ready-made default look, use [CrdtAwarenessCursorsOverlay].
///
/// ## Example
/// ```dart
/// CrdtAwarenessCursorsBuilder(
///   cursors: remotePointers,
///   onLocalPointer: (position, {required hovering}) =>
///       publishPresence(position, hovering),
///   builder: (context, cursor) => CrdtAwarenessCursorMarker(
///     color: cursor.color,
///     label: cursor.label,
///     hovering: cursor.hovering,
///   ),
///   child: pane,
/// ),
/// ```
/// {@endtemplate}
class CrdtAwarenessCursorsBuilder extends StatelessWidget {
  /// {@macro crdt_awareness_cursors_builder}
  const CrdtAwarenessCursorsBuilder({
    required this.cursors,
    required this.builder,
    required this.child,
    this.onLocalPointer,
    super.key,
  });

  /// The remote pointers to lay out.
  final List<CrdtAwarenessCursor> cursors;

  /// Builds the widget drawn at each cursor's pointer.
  final CrdtAwarenessCursorWidgetBuilder builder;

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
                          child: builder(context, cursor),
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

/// {@template crdt_awareness_cursors_overlay}
/// Overlays the mouse-style presence cursors of remote collaborators on top
/// of [child], and reports the local pointer through [onLocalPointer] so
/// the app can publish it on its presence channel.
///
/// This is the ready-made overlay: each cursor is drawn with the
/// default [CrdtAwarenessCursorMarker], colored with its own
/// [CrdtAwarenessCursor.color]. Pass a [style] to restyle every cursor at
/// once (a cursor's own [CrdtAwarenessCursor.style] still wins); for
/// per-cursor control or a completely different marker, drop down to
/// [CrdtAwarenessCursorsBuilder].
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
    this.style,
    super.key,
  });

  /// The remote pointers to draw.
  final List<CrdtAwarenessCursor> cursors;

  /// Called with the local pointer position (normalized into `[0, 1]`) on
  /// hover, and with `hovering: false` when the pointer leaves the pane.
  final CrdtLocalPointerCallback? onLocalPointer;

  /// Shared style applied to every cursor that doesn't carry its own
  /// [CrdtAwarenessCursor.style]. Its color is always overridden by the
  /// per-cursor [CrdtAwarenessCursor.color] (so peers keep their identity
  /// color); this controls the rest (label text style, sizes). Defaults to
  /// [CrdtAwarenessCursorStyle.new].
  final CrdtAwarenessCursorStyle? style;

  /// The wrapped pane content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? const CrdtAwarenessCursorStyle();
    return CrdtAwarenessCursorsBuilder(
      cursors: cursors,
      onLocalPointer: onLocalPointer,
      // The peer's color always wins for identity; the style (per-cursor, or
      // the shared one) supplies the rest.
      builder: (context, cursor) => CrdtAwarenessCursorMarker(
        label: cursor.label,
        hovering: cursor.hovering,
        style: (cursor.style ?? baseStyle).copyWith(color: cursor.color),
      ),
      child: child,
    );
  }
}

/// {@template crdt_awareness_cursor_style}
/// The full look of a [CrdtAwarenessCursorMarker]: the [color] (pointer arrow
/// and name-bubble background), the [labelStyle] of the name text and the
/// marker geometry.
///
/// This is the "decoration" half of the marker's `Container`-style API: pass
/// the marker's plain `color` for the common case, or a full
/// [CrdtAwarenessCursorStyle] when you also want to change the text color,
/// sizes, etc. (set [labelStyle]'s `color` for the name text color).
/// {@endtemplate}
@immutable
class CrdtAwarenessCursorStyle {
  /// {@macro crdt_awareness_cursor_style}
  const CrdtAwarenessCursorStyle({
    this.color = const Color(0xFF2196F3),
    this.labelStyle,
    this.pointerSize = 18,
    this.bubbleHeight = 18,
    this.maxBubbleWidth = 140,
  });

  /// Pointer arrow fill and name-bubble background.
  final Color color;

  /// Name-bubble text style, merged over the default (white, 11px, w600) —
  /// set its `color` to change the text color.
  final TextStyle? labelStyle;

  /// The size of the (square) pointer arrow.
  final double pointerSize;

  /// The height of the name bubble; also its corner radius (a pill).
  final double bubbleHeight;

  /// The maximum name-bubble width; longer names are truncated with an
  /// ellipsis.
  final double maxBubbleWidth;

  static const _defaultLabelStyle = TextStyle(
    color: Color(0xFFFFFFFF),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// The name text style actually painted: [labelStyle] merged over the
  /// default white pill text.
  TextStyle get resolvedLabelStyle => _defaultLabelStyle.merge(labelStyle);

  /// A copy of this style with the given fields replaced.
  CrdtAwarenessCursorStyle copyWith({
    Color? color,
    TextStyle? labelStyle,
    double? pointerSize,
    double? bubbleHeight,
    double? maxBubbleWidth,
  }) {
    return CrdtAwarenessCursorStyle(
      color: color ?? this.color,
      labelStyle: labelStyle ?? this.labelStyle,
      pointerSize: pointerSize ?? this.pointerSize,
      bubbleHeight: bubbleHeight ?? this.bubbleHeight,
      maxBubbleWidth: maxBubbleWidth ?? this.maxBubbleWidth,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CrdtAwarenessCursorStyle &&
      other.color == color &&
      other.labelStyle == labelStyle &&
      other.pointerSize == pointerSize &&
      other.bubbleHeight == bubbleHeight &&
      other.maxBubbleWidth == maxBubbleWidth;

  @override
  int get hashCode => Object.hash(
        color,
        labelStyle,
        pointerSize,
        bubbleHeight,
        maxBubbleWidth,
      );
}

/// Name-bubble layout: the bubble hangs at the pointer's bottom-right with a
/// small gap, so the arrow and bubble read as two elements, not one blob.
const double _kBubblePadding = 8;
const Offset _kBubbleOffset = Offset(12, 3);

/// {@template crdt_awareness_cursor_marker}
/// The standalone visual marker for a single collaborator's pointer: a
/// Figma-style arrow and an optional name bubble. Positioning is the caller's
/// job (its top-left sits at the pointer) — [CrdtAwarenessCursorsBuilder] and
/// [CrdtAwarenessCursorsOverlay] place it for you.
///
/// Styled `Container`-style: pass a plain `color` for the common case, or a
/// full `style` ([CrdtAwarenessCursorStyle]) to also control the text color,
/// sizes, etc. Passing both is an error.
///
/// ## Example
/// ```dart
/// CrdtAwarenessCursorMarker(label: 'Bob', color: Colors.pink);
/// ```
/// {@endtemplate}
class CrdtAwarenessCursorMarker extends StatelessWidget {
  /// {@macro crdt_awareness_cursor_marker}
  CrdtAwarenessCursorMarker({
    this.label,
    this.hovering = false,
    Color? color,
    CrdtAwarenessCursorStyle? style,
    super.key,
  })  : assert(
          color == null || style == null,
          'Cannot provide both `color` and `style`. Set '
          'CrdtAwarenessCursorStyle.color to color a fully-styled marker.',
        ),
        style = style ??
            (color == null
                ? const CrdtAwarenessCursorStyle()
                : CrdtAwarenessCursorStyle(color: color));

  /// Name bubble drawn under the pointer; omitted when `null`.
  final String? label;

  /// Whether the pointer is hovering the pane; the arrow grows slightly.
  final bool hovering;

  /// The resolved look of the marker.
  final CrdtAwarenessCursorStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pointer tip at the widget's top-left ~ the actual position.
        // Grows smoothly while the collaborator is hovering.
        AnimatedScale(
          scale: hovering ? 1.25 : 1,
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.topLeft,
          child: CustomPaint(
            size: Size(style.pointerSize, style.pointerSize),
            painter: _PointerPainter(color: style.color),
          ),
        ),
        // Name bubble: fixed height, capped width, long names truncated.
        if (label != null)
          Padding(
            padding: EdgeInsets.only(
              left: _kBubbleOffset.dx,
              top: _kBubbleOffset.dy,
            ),
            child: Container(
              height: style.bubbleHeight,
              constraints: BoxConstraints(maxWidth: style.maxBubbleWidth),
              padding: const EdgeInsets.symmetric(horizontal: _kBubblePadding),
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(style.bubbleHeight / 2),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.resolvedLabelStyle,
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
