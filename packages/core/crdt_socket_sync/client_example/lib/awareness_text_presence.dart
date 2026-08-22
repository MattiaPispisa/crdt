import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// [TextCursorPresence] mapped onto the awareness plugin.
///
/// The local selection anchors are published under the `textCursors`
/// metadata key — `{handlerId: {'base': …, 'extent': …}}`, base64 so the
/// map stays JSON-safe. `updateLocalState` merges by top-level key, so
/// publishing cursors never disturbs the other presence metadata (`name`,
/// mouse position).
///
/// Remote awareness states are mapped back to [CrdtTextCursor]s, colored
/// with [peerColorFor] — the same color as the peer's mouse cursor.
class AwarenessTextCursorPresence extends BaseTextCursorPresence {
  /// Creates the presence bridge over [awareness].
  ///
  /// [localSessionId] is read lazily (per awareness event): the session id
  /// is only assigned once the client is connected.
  AwarenessTextCursorPresence({
    required ClientAwarenessPlugin awareness,
    required String? Function() localSessionId,
  }) : _awareness = awareness,
       _localSessionId = localSessionId {
    _subscription = awareness.awarenessStream.listen(_onAwareness);
    _onAwareness(awareness.awareness);
  }

  final ClientAwarenessPlugin _awareness;
  final String? Function() _localSessionId;

  /// The local anchors last published, per text handler id (the metadata
  /// key is replaced wholesale on every publish).
  final _local = <String, Map<String, String?>>{};

  late final StreamSubscription<DocumentAwareness> _subscription;

  @override
  void publish(String handlerId, FugueElementID? base, FugueElementID? extent) {
    if (base == null) {
      _local.remove(handlerId);
    } else {
      _local[handlerId] = {
        'base': encodeTextAnchor(base),
        'extent': encodeTextAnchor(extent),
      };
    }
    _awareness.updateLocalState({'textCursors': _local});
  }

  void _onAwareness(DocumentAwareness awareness) {
    final myId = _localSessionId();
    final byHandler = <String, List<CrdtTextCursor>>{};
    for (final entry in awareness.states.entries) {
      if (entry.key == myId) {
        continue;
      }
      final metadata = entry.value.metadata;
      final cursors = metadata['textCursors'];
      if (cursors is! Map<String, dynamic>) {
        continue;
      }
      final name = metadata['name'] as String?;
      for (final cursorEntry in cursors.entries) {
        final anchors = cursorEntry.value;
        if (anchors is! Map<String, dynamic>) {
          continue;
        }
        final base = decodeTextAnchor(anchors['base'] as String?);
        if (base == null) {
          continue;
        }
        byHandler
            .putIfAbsent(cursorEntry.key, () => [])
            .add(
              CrdtTextCursor(
                id: entry.key,
                color: peerColorFor(entry.key),
                label: (name?.trim().isNotEmpty ?? false) ? name : 'anon',
                base: base,
                extent: decodeTextAnchor(anchors['extent'] as String?),
              ),
            );
      }
    }
    setRemoteCursors(byHandler);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
