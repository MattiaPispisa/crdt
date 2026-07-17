import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_client_example/socket_sync_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// Bridges the awareness plugin to a [CrdtAwarenessCursorsOverlay] over
/// [child]: remote peer states become [CrdtAwarenessCursor]s and the local
/// pointer is reported back so other peers can render this device's cursor.
///
/// Reusable: wrap any example pane with it (see `ExampleScaffold.paneWrapper`).
/// Positions travel normalized in `[0, 1]` (the overlay's convention), so
/// cursors map correctly across windows of different sizes.
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

  void _report(Offset position, {required bool hovering}) {
    session.awareness.updateLocalState({
      'positionX': position.dx,
      'positionY': position.dy,
      'isHovering': hovering,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentAwareness>(
      stream: _awareness.awarenessStream,
      initialData: _awareness.awareness,
      builder:
          (context, snapshot) => CrdtAwarenessCursorsOverlay(
            cursors: _remoteCursors(snapshot.data),
            onLocalPointer: _report,
            child: child,
          ),
    );
  }

  /// Builds the list of remote cursors from [awareness], excluding this device.
  List<CrdtAwarenessCursor> _remoteCursors(DocumentAwareness? awareness) {
    final myId = session.client.sessionId;
    final states = awareness?.states ?? const {};
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
