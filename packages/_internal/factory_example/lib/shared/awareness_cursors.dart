import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:factory_example/shared/peer_colors.dart';
import 'package:flutter/material.dart';

/// Bridges the awareness plugin to a [CrdtAwarenessCursorsOverlay] over
/// [child]: remote peer states become [CrdtAwarenessCursor]s and the local
/// pointer is reported back so other peers can render this device's cursor.
///
/// Positions travel normalized in `[0, 1]` (the overlay's convention), so
/// cursors map correctly across windows of different sizes.
class AwarenessCursors extends StatelessWidget {
  /// Creates the cursor overlay driven by [awareness].
  const AwarenessCursors({
    required this.awareness,
    required this.child,
    super.key,
  });

  /// The awareness plugin of the pane's client.
  final ClientAwarenessPlugin awareness;

  /// The wrapped pane content.
  final Widget child;

  void _report(Offset position, {required bool hovering}) {
    awareness.updateLocalState({
      'positionX': position.dx,
      'positionY': position.dy,
      'isHovering': hovering,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentAwareness>(
      stream: awareness.awarenessStream,
      initialData: awareness.awareness,
      builder:
          (context, snapshot) => CrdtAwarenessCursorsOverlay(
            cursors: _remoteCursors(snapshot.data),
            onLocalPointer: _report,
            child: child,
          ),
    );
  }

  /// Builds the list of remote cursors from [state], excluding this device.
  List<CrdtAwarenessCursor> _remoteCursors(DocumentAwareness? state) {
    final myId = awareness.client.sessionId;
    final states = state?.states ?? const {};
    final result = <CrdtAwarenessCursor>[];
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
      final name = metadata['name'] as String?;
      result.add(
        CrdtAwarenessCursor(
          id: entry.key,
          label: (name?.trim().isNotEmpty ?? false) ? name : 'anon',
          color: peerColorFor(entry.key),
          position: Offset(x, y),
          hovering: metadata['isHovering'] as bool? ?? false,
        ),
      );
    }
    return result;
  }
}
