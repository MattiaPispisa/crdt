import 'dart:math' as math;

import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_client_example/socket_sync_session.dart';
import 'package:flutter/material.dart';

/// Maximum width of a cursor's name bubble; the name is scaled down to fit so
/// it never grows enough to cover the UI.
const double _kMaxBubbleWidth = 140;
const double _kBubbleHeight = 22;

/// Overlays live remote peer cursors (from the awareness plugin) on top of
/// [child], and reports the local pointer position back to the awareness
/// plugin so other peers can render this device's cursor.
///
/// Reusable: wrap any example pane with it (see `ExampleScaffold.paneWrapper`).
/// Positions are stored normalized in `[0, 1]`, so cursors map correctly across
/// windows of different sizes.
class AwarenessCursors extends StatelessWidget {
  /// Creates the cursor overlay for [session].
  const AwarenessCursors({
    super.key,
    required this.session,
    required this.child,
  });

  /// The socket session whose awareness plugin drives the cursors.
  final SocketSyncSession session;

  /// The wrapped pane content.
  final Widget child;

  ClientAwarenessPlugin get _awareness => session.awareness;

  void _report(Size size, Offset local, {required bool hovering}) {
    if (size.isEmpty) {
      return;
    }
    session.awareness.updateLocalState({
      'positionX': (local.dx / size.width).clamp(0.0, 1.0),
      'positionY': (local.dy / size.height).clamp(0.0, 1.0),
      'isHovering': hovering,
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          opaque: false,
          onHover:
              (event) => _report(size, event.localPosition, hovering: true),
          onExit:
              (_) => session.awareness.updateLocalState({'isHovering': false}),
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Positioned.fill(
                child: IgnorePointer(
                  child: StreamBuilder<DocumentAwareness>(
                    stream: _awareness.awarenessStream,
                    initialData: _awareness.awareness,
                    builder: (context, snapshot) {
                      final cursors = _remoteCursors(snapshot.data);
                      return Stack(
                        children: [
                          for (final cursor in cursors)
                            AnimatedPositioned(
                              key: ValueKey(cursor.id),
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              left: cursor.normalized.dx * size.width,
                              top: cursor.normalized.dy * size.height,
                              child: _CursorMarker(
                                name: cursor.name,
                                color: cursor.color,
                                hovering: cursor.hovering,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the list of remote cursors from [awareness], excluding this device.
  List<_RemoteCursor> _remoteCursors(DocumentAwareness? awareness) {
    final myId = session.client.sessionId;
    final states = awareness?.states ?? const {};
    final result = <_RemoteCursor>[];
    for (final entry in states.entries) {
      if (entry.key == myId) {
        continue;
      }
      final metadata = entry.value.metadata;
      final x = (metadata['positionX'] as num?)?.toDouble();
      final y = (metadata['positionY'] as num?)?.toDouble();
      if (x == null || y == null) {
        continue;
      }
      result.add(
        _RemoteCursor(
          id: entry.key,
          name:
              (metadata['name'] as String?)?.trim().isNotEmpty ?? false
                  ? metadata['name'] as String
                  : 'anon',
          normalized: Offset(x, y),
          hovering: metadata['isHovering'] as bool? ?? false,
        ),
      );
    }
    return result;
  }
}

/// A remote peer's cursor state, resolved for rendering.
class _RemoteCursor {
  _RemoteCursor({
    required this.id,
    required this.name,
    required this.normalized,
    required this.hovering,
  }) : color = _colorFor(id);

  final String id;
  final String name;
  final Offset normalized;
  final bool hovering;
  final Color color;
}

/// A pointer arrow plus a name bubble bounded to [_kMaxBubbleWidth].
class _CursorMarker extends StatelessWidget {
  const _CursorMarker({
    required this.name,
    required this.color,
    required this.hovering,
  });

  final String name;
  final Color color;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cursor tip (points up-left, so its top-left ~ the actual position).
        Transform.rotate(
          angle: -math.pi / 4,
          child: Icon(Icons.navigation, size: hovering ? 20 : 16, color: color),
        ),
        // Name bubble: fixed height, capped width, text scaled to fit.
        Container(
          height: _kBubbleHeight,
          constraints: const BoxConstraints(maxWidth: _kMaxBubbleWidth),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_kBubbleHeight / 2),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Deterministic vibrant color from a peer id.
Color _colorFor(String id) {
  const colors = [
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF5E35B1),
    Color(0xFF3949AB),
    Color(0xFF1E88E5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF00ACC1),
    Color(0xFFFB8C00),
  ];
  return colors[id.hashCode.abs() % colors.length];
}
